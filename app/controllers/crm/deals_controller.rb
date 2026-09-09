# frozen_string_literal: true

module Crm
  class DealsController < BaseController
    crm_model CrmDeal

    accept_api_auth :index, :show, :create, :update, :archive, :restore, :move, :lookup

    before_action :require_crm_read, :only => [:index, :show]
    before_action :find_record, :only => [:show, :edit, :update, :archive, :restore, :move]
    before_action :require_staff, :only => [:new, :create, :edit, :update, :archive, :restore, :bulk, :board, :move]

    def index
      setup_index(CrmDealQuery, CrmDeal, :order => 'next_action_on ASC NULLS LAST, id ASC')
      return if performed?

      render
    end

    def show
      prepare_record_page
      render
    end

    def new
      crm_record_alias(CrmDeal.new)
      render
    end

    def create
      attributes = record_params(CrmDeal)
      if (existing = existing_external_identity(attributes, CrmDeal))
        return render_existing(existing)
      end

      crm_record_alias(CrmDeal.new)
      return unless precheck_safe_attributes!(@record, attributes)
      return unless assign_record_attributes(@record, attributes, :create => true)

      if @record.save
        render_mutation_success(@record, :status => :created)
      else
        render_record_errors(@record)
      end
    rescue ActiveRecord::RecordNotUnique
      existing = existing_external_identity(attributes, CrmDeal)
      existing ? render_existing(existing) : render_json_error(:error => 'conflict', :messages => [], :status => :conflict)
    rescue ActiveRecord::RecordInvalid => exception
      render_record_errors(exception.record)
    end

    def edit
      render
    end

    def update
      attributes = record_params(CrmDeal)
      return unless precheck_safe_attributes!(@record, attributes)
      return unless assign_record_attributes(@record, attributes)

      if @record.save
        render_mutation_success(@record)
      else
        render_record_errors(@record)
      end
    rescue ActiveRecord::RecordInvalid => exception
      render_record_errors(exception.record)
    end

    def archive
      return unless with_lock_version(@record) { @record.archive!(crm_user) }

      render_mutation_success(@record)
    rescue ActiveRecord::RecordInvalid => exception
      render_record_errors(exception.record)
    end

    def restore
      return unless with_lock_version(@record) { @record.restore!(crm_user) }

      render_mutation_success(@record)
    rescue ActiveRecord::RecordInvalid => exception
      render_record_errors(exception.record)
    rescue ActiveRecord::RecordNotUnique
      render_json_error(:error => 'conflict', :messages => [], :status => :conflict)
    end


    def bulk
      visible = crm_visible_scope(CrmDeal, :include_archived => true)
      common = params[:attributes] || params[:values] || {}
      results = []

      bulk_items.each do |id, raw_values|
        values = raw_values.presence || common
        values = values.to_unsafe_h if values.respond_to?(:to_unsafe_h)
        values = values.to_h if values.respond_to?(:to_h) && !values.is_a?(Hash)
        values = values.stringify_keys
        record = visible.find_by(:id => id)
        unless record
          results << {:id => id.to_i, :error => 'not_found'}
          next
        end

        action = values.delete('action') || params[:bulk_action].to_s
        begin
          if %w[archive restore].include?(action) && record.respond_to?(:lock_version) &&
              (values['lock_version'].blank? || record.lock_version.to_i != values['lock_version'].to_i)
            results << {:id => record.id, :error => 'conflict'}
            next
          end
          if action == 'archive'
            record.archive!(crm_user)
          elsif action == 'restore'
            record.restore!(crm_user)
          elsif values['stage_id'].present?
            stage = CrmPipelineStage.find_by(:id => values['stage_id'])
            raise ActiveRecord::RecordInvalid.new(record) unless stage && stage.pipeline_id.to_i == record.pipeline_id.to_i

            moved = Crm::MoveDeal.call(:deal => record, :stage => stage, :user => crm_user, :lock_version => values['lock_version'])
            record = moved.respond_to?(:deal) ? moved.deal : (moved || record)
          else
            prepared, error = prepared_record_attributes(record, values)
            if error
              results << error.merge(:id => record.id)
              next
            end
            record.safe_attributes = prepared
            record.save!
          end
          results << {:id => record.id, :ok => true, :lock_version => record.try(:lock_version)}
        rescue ActiveRecord::StaleObjectError
          results << {:id => record.id, :error => 'conflict'}
        rescue ActiveRecord::RecordInvalid => exception
          results << {:id => record.id, :error => 'validation', :messages => exception.record.errors.full_messages}
        end
      end

      render :json => {:results => results}, :status => :ok
    end

    def board
      @pipeline = CrmPipeline.find_by(:is_default => true)
      @stages = @pipeline ? @pipeline.stages.order(:position).to_a : []
      deals = if @pipeline
                scope = CrmDeal.visible(crm_user)
                scope = scope.active if scope.respond_to?(:active)
                scope.where(:pipeline_id => @pipeline.id).to_a
              else
                []
              end
      @deals_by_stage = deals.group_by(&:stage_id)
      @totals_by_stage = {}
      if crm_money?
        @stages.each do |stage|
          @totals_by_stage[stage.id] = deals.select {|deal| deal.stage_id == stage.id}.group_by(&:currency).transform_values do |rows|
            rows.sum {|deal| deal.amount_cents.to_i }
          end
        end
      end
      render
    end

    def move
      attributes = record_params(CrmDeal)
      stage = CrmPipelineStage.find_by(:id => attributes['stage_id'] || params[:stage_id])
      return render_json_error(:error => 'validation', :messages => ['stage is required'], :status => :unprocessable_entity) unless stage
      return render_json_error(:error => 'validation', :messages => ['stage does not belong to deal pipeline'], :status => :unprocessable_entity) unless stage.pipeline_id.to_i == @record.pipeline_id.to_i

      moved = Crm::MoveDeal.call(:deal => @record, :stage => stage, :user => crm_user, :lock_version => attributes['lock_version'] || params[:lock_version])
      moved = moved.respond_to?(:deal) ? moved.deal : (moved || @record)
      render_mutation_success(moved)
    rescue ActiveRecord::RecordInvalid => exception
      render_record_errors(exception.record)
    end

    def lookup
      return unless require_lookup_access

      external_ref = params[:external_ref].to_s
      return render_404 if external_ref.blank?

      record = CrmDeal.unscoped.find_by(:external_ref => external_ref)
      return render_404 unless record

      seen = {}
      while record.respond_to?(:merged_into_id) && record.merged_into_id.present? && !seen[record.id]
        seen[record.id] = true
        record = CrmDeal.unscoped.find_by(:id => record.merged_into_id)
        break unless record
      end
      return render_404 unless record

      respond_to do |format|
        format.xml { render :xml => {:id => record.id}, :status => :ok }
        format.json { render :json => {:id => record.id}, :status => :ok }
      end
    end

    private

    def require_lookup_access
      return true if Crm::Access.staff?(crm_user) || Crm::Access.feed?(crm_user)

      render_403
      false
    end

    def crm_feed_action_allowed?
      action_name.to_s == 'lookup'
    end
  end
end
