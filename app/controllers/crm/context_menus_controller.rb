# frozen_string_literal: true

module Crm
  class ContextMenusController < BaseController
    helper :context_menus

    RECORD_CLASSES = {
      'accounts' => CrmAccount,
      'contacts' => CrmContact,
      'deals' => CrmDeal,
      'activities' => CrmActivity
    }.freeze

    before_action :require_staff
    before_action :find_context_records

    def show
      @back = params[:back_url].presence || url_for(:action => :index)
      @record_ids = @records.map(&:id)
      @record = @records.one? ? @records.first : nil
      @owners = User.where(:status => User::STATUS_ACTIVE).
        order(:lastname, :firstname, :id).to_a
      @stages = context_stages
      @has_active = @records.any? {|record| !record_archived?(record) }
      @has_archived = @records.any? {|record| record_archived?(record) }
      render :template => "crm/context_menus/#{@record_type}", :layout => false
    end

    private

    def find_context_records
      @record_type = params[:type].to_s.pluralize
      klass = RECORD_CLASSES[@record_type]
      return render_404 unless klass

      ids = Array(params[:ids].presence || params[:id]).flat_map do |value|
        value.to_s.split(',')
      end.map(&:to_i).select(&:positive?).uniq
      return render_404 if ids.empty?

      @records = crm_visible_scope(klass, :include_archived => true).
        where(:id => ids).to_a
      render_404 if @records.empty?
    end

    def context_stages
      return [] unless @record_type == 'deals'

      pipeline_ids = @records.map(&:pipeline_id).compact.uniq
      return [] unless pipeline_ids.one?

      CrmPipelineStage.where(:pipeline_id => pipeline_ids.first).
        order(:position, :id).to_a
    end

    def record_archived?(record)
      record.respond_to?(:archived?) ? record.archived? : record.archived_on.present?
    end
  end
end
