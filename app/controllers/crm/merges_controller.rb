# frozen_string_literal: true

module Crm
  class MergesController < BaseController
    before_action :require_login
    before_action :require_staff

    def new
      return head(:forbidden) if api_request?

      @source = source_record
      @preview = nil
      if params[:target_id].present?
        target = source_class.visible(User.current).find(params[:target_id])
        @preview = Crm::Merge.preview(@source, target, User.current)
      end
      render :new
    rescue ActiveRecord::RecordNotFound
      render_404
    end

    def create
      return head(:forbidden) if api_request?

      source = source_record
      target = source_class.visible(User.current).find(params[:target_id])
      survivor = Crm::Merge.call(:source => source, :target => target, :user => User.current)
      survivor = survivor.respond_to?(:record) ? survivor.record : survivor
      redirect_to crm_record_path(survivor)
    rescue ActiveRecord::RecordNotFound
      render_404
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ArgumentError => e
      @source = source rescue nil
      @preview = nil
      if @source && params[:target_id].present?
        target = source_class.visible(User.current).find_by(:id => params[:target_id])
        @preview = Crm::Merge.preview(@source, target, User.current) if target
      end
      flash.now[:error] = e.message
      render :new, :status => :unprocessable_content
    end

    private

    def record_type
      params[:record_type].to_s.presence || 'account'
    end

    def source_class
      {'account' => CrmAccount, 'contact' => CrmContact}.fetch(record_type)
    rescue KeyError
      raise ActiveRecord::RecordNotFound
    end

    def source_record
      source_class.visible(User.current).find(params[:id])
    end

    def crm_record_path(record)
      record.is_a?(CrmAccount) ? crm_account_path(record) : crm_contact_path(record)
    end
  end
end
