# frozen_string_literal: true

module Crm
  class ContactsController < BaseController
    crm_model CrmContact

    accept_api_auth :index, :show, :create, :update, :archive, :restore, :lookup

    before_action :require_crm_read, :only => [:index, :show]
    before_action :find_record, :only => [:show, :edit, :update, :archive, :restore]
    before_action :require_staff, :only => [:new, :create, :edit, :update, :archive, :restore, :bulk]

    def index
      setup_index(CrmContactQuery, CrmContact, :order => 'last_name ASC, first_name ASC, id ASC')
      return if performed?

      render
    end

    def show
      prepare_record_page
      render
    end

    def new
      crm_record_alias(CrmContact.new)
      render
    end

    def create
      attributes = record_params(CrmContact)
      if (existing = existing_external_identity(attributes, CrmContact))
        return render_existing(existing)
      end

      crm_record_alias(CrmContact.new)
      return unless precheck_safe_attributes!(@record, attributes)
      return unless assign_record_attributes(@record, attributes, :create => true)

      @record.save_attachments(params[:attachments])
      if @record.save
        render_attachment_warning_if_needed(@record)
        render_mutation_success(@record, :status => :created)
      else
        render_record_errors(@record)
      end
    rescue ActiveRecord::RecordNotUnique
      existing = existing_external_identity(attributes, CrmContact)
      existing ? render_existing(existing) : render_json_error(:error => 'conflict', :messages => [], :status => :conflict)
    rescue ActiveRecord::RecordInvalid => exception
      render_record_errors(exception.record)
    end

    def edit
      render
    end

    def update
      attributes = record_params(CrmContact)
      return unless precheck_safe_attributes!(@record, attributes)
      return unless assign_record_attributes(@record, attributes)

      @record.save_attachments(params[:attachments])
      if @record.save
        render_attachment_warning_if_needed(@record)
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
      bulk_mutate_records(CrmContact)
    end

    def lookup
      return unless require_lookup_access

      external_ref = params[:external_ref].to_s
      return render_404 if external_ref.blank?

      record = CrmContact.unscoped.find_by(:external_ref => external_ref)
      return render_404 unless record

      seen = {}
      while record.respond_to?(:merged_into_id) && record.merged_into_id.present? && !seen[record.id]
        seen[record.id] = true
        record = CrmContact.unscoped.find_by(:id => record.merged_into_id)
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
