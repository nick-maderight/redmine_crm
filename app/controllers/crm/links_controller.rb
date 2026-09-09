# frozen_string_literal: true

module Crm
  class LinksController < BaseController
    before_action :require_staff
    accept_api_auth :create, :destroy

    def create

      record = linked_record
      issue = Issue.visible.find(params[:issue_id] || params.dig(:link, :issue_id))
      attributes = {:issue_id => issue.id, record_key => record.id, :created_on => Time.current}
      link = CrmLink.find_by(:issue_id => issue.id, record_key => record.id)
      created = false
      unless link
        link = CrmLink.new(attributes)
        unless link.save
          return render_link_error(link)
        end
        created = true
        record.crm_change!('link_issue', nil, issue.id.to_s, User.current) if record.respond_to?(:crm_change!)
      end
      respond_to do |format|
        format.html { redirect_to crm_record_path(record) }
        format.api { render :json => link_payload(link), :status => created ? :created : :ok }
        format.json { render :json => link_payload(link), :status => created ? :created : :ok }
      end
    rescue ActiveRecord::RecordNotFound
      render_404
    rescue ActiveRecord::RecordNotUnique
      link = CrmLink.find_by(:issue_id => issue.id, record_key => record.id)
      respond_to do |format|
        format.api { render :json => link_payload(link), :status => :ok }
        format.json { render :json => link_payload(link), :status => :ok }
        format.html { redirect_to crm_record_path(record) }
      end
    end

    def destroy

      link = CrmLink.find(params[:id])
      record = link_record(link)
      return render_404 unless record && record.visible?(User.current)

      issue_id = link.issue_id
      link.destroy!
      record.crm_change!('link_issue', issue_id.to_s, nil, User.current) if record.respond_to?(:crm_change!)
      respond_to do |format|
        format.html { redirect_to crm_record_path(record) }
        format.api { render :json => {:id => link.id, :deleted => true}, :status => :ok }
        format.json { render :json => {:id => link.id, :deleted => true}, :status => :ok }
      end
    rescue ActiveRecord::RecordNotFound
      render_404
    end

    private

    def record_type
      params[:record_type].to_s.presence || 'account'
    end

    def record_key
      case record_type
      when 'account' then :account_id
      when 'contact' then :contact_id
      when 'deal' then :deal_id
      else
        raise ActiveRecord::RecordNotFound
      end
    end

    def linked_record
      klass = {'account' => CrmAccount, 'contact' => CrmContact, 'deal' => CrmDeal}.fetch(record_type)
      klass.visible(User.current).find(params[:id])
    end

    def link_record(link)
      link.account || link.contact || link.deal
    end

    def crm_record_path(record)
      case record
      when CrmAccount then crm_account_path(record)
      when CrmContact then crm_contact_path(record)
      else crm_deal_path(record)
      end
    end

    def link_payload(link)
      type = if link.account_id.present?
               'account'
             elsif link.contact_id.present?
               'contact'
             else
               'deal'
             end
      {:id => link.id, :issue_id => link.issue_id,
       :record_type => type, :record_id => (link.account_id || link.contact_id || link.deal_id)}
    end

    def render_link_error(link)
      respond_to do |format|
        format.html { render :plain => link.errors.full_messages.join(', '), :status => :unprocessable_content }
        format.api { render :json => {:errors => link.errors.full_messages}, :status => :unprocessable_content }
        format.json { render :json => {:errors => link.errors.full_messages}, :status => :unprocessable_content }
      end
    end
  end
end
