# frozen_string_literal: true

module Crm
  class PipelinesController < BaseController
    before_action :require_login
    before_action :require_admin
    before_action :find_pipeline, :only => [:update, :destroy]
    accept_api_auth :index

    def index
      @pipelines = CrmPipeline.includes(:stages).order(:position, :id).to_a
      respond_to do |format|
        format.html
        format.api
        format.json { render :json => @pipelines.map { |pipeline| pipeline_json(pipeline) } }
      end
    end

    def create
      @pipeline = CrmPipeline.new
      attrs = record_params(CrmPipeline)
      return unless precheck_safe_attributes!(@pipeline, attrs)

      @pipeline.safe_attributes = attrs
      if @pipeline.save
        respond_to do |format|
          format.html { redirect_to crm_pipelines_path }
          format.json { render :json => pipeline_json(@pipeline), :status => :created }
        end
      else
        render_pipeline_errors
      end
    rescue ActiveRecord::RecordNotUnique
      @pipeline.errors.add(:name, :taken)
      render_pipeline_errors
    end

    def update
      attrs = record_params(CrmPipeline)
      return unless precheck_safe_attributes!(@pipeline, attrs)

      @pipeline.safe_attributes = attrs
      if @pipeline.save
        respond_to do |format|
          format.html { redirect_to crm_pipelines_path }
          format.json { render :json => pipeline_json(@pipeline), :status => :ok }
        end
      else
        render_pipeline_errors
      end
    rescue ActiveRecord::RecordNotUnique
      @pipeline.errors.add(:name, :taken)
      render_pipeline_errors
    end

    def destroy
      if @pipeline.destroy
        respond_to do |format|
          format.html { redirect_to crm_pipelines_path }
          format.json { render :json => {:id => @pipeline.id, :deleted => true}, :status => :ok }
        end
      else
        render_pipeline_errors
      end
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey => e
      @pipeline.errors.add(:base, e.message)
      render_pipeline_errors
    end

    private

    def find_pipeline
      @pipeline = CrmPipeline.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render_404
    end

    def render_pipeline_errors
      @pipelines ||= CrmPipeline.includes(:stages).order(:position, :id).to_a
      respond_to do |format|
        format.html { render :index, :status => :unprocessable_content }
        format.api { render :json => {:errors => @pipeline.errors.full_messages}, :status => :unprocessable_content }
        format.json { render :json => {:errors => @pipeline.errors.full_messages}, :status => :unprocessable_content }
      end
    end

    def pipeline_json(pipeline)
      {
        :id => pipeline.id,
        :name => pipeline.name,
        :position => pipeline.position,
        :is_default => pipeline.is_default,
        :stages => pipeline.stages.map do |stage|
          {:id => stage.id, :name => stage.name, :position => stage.position,
           :probability => stage.probability, :kind => stage.kind, :color => stage.color,
           :followup_text => stage.followup_text, :followup_due_days => stage.followup_due_days}
        end
      }
    end
  end
end
