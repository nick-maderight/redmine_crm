# frozen_string_literal: true

module Crm
  class ActivitiesController < BaseController
    crm_model CrmActivity

    accept_api_auth :index, :show, :create, :update, :archive, :restore

    before_action :require_crm_read, :only => [:index, :show]
    before_action :find_record, :only => [:show, :edit, :update, :archive, :restore]
    before_action :require_staff, :only => [:new, :create, :edit, :update, :archive, :restore, :bulk]

    def index
      setup_index(CrmActivityQuery, CrmActivity, :order => 'occurred_at DESC NULLS LAST, id DESC')
      return if performed?

      render
    end

    def show
      prepare_record_page
      render
    end

    def new
      crm_record_alias(CrmActivity.new)
      render
    end

    def create
      attributes = record_params(CrmActivity)
      if (existing = existing_external_identity(attributes, CrmActivity))
        return render_existing(existing)
      end

      crm_record_alias(CrmActivity.new)
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
      existing = existing_external_identity(attributes, CrmActivity)
      existing ? render_existing(existing) : render_json_error(:error => 'conflict', :messages => [], :status => :conflict)
    rescue ActiveRecord::RecordInvalid => exception
      render_record_errors(exception.record)
    end

    def edit
      render
    end

    def update
      attributes = record_params(CrmActivity)
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
      bulk_mutate_records(CrmActivity)
    end
  end
end
