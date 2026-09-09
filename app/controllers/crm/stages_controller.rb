# frozen_string_literal: true

module Crm
  class StagesController < BaseController
    before_action :require_login
    before_action :require_admin
    before_action :find_stage, :only => [:update, :destroy]

    def create
      @pipeline = CrmPipeline.find(params[:pipeline_id])
      @stage = @pipeline.stages.build
      attrs = record_params(CrmPipelineStage)
      return unless precheck_safe_attributes!(@stage, attrs)

      @stage.safe_attributes = attrs
      if @stage.save
        respond_to do |format|
          format.html { redirect_to crm_pipelines_path }
          format.json { render :json => stage_json(@stage), :status => :created }
        end
      else
        render_stage_errors
      end
    rescue ActiveRecord::RecordNotFound
      render_404
    rescue ActiveRecord::RecordNotUnique
      @stage.errors.add(:name, :taken)
      render_stage_errors
    end

    def update
      @pipeline = @stage.pipeline
      attrs = record_params(CrmPipelineStage)
      return unless precheck_safe_attributes!(@stage, attrs)

      @stage.safe_attributes = attrs
      if @stage.save
        respond_to do |format|
          format.html { redirect_to crm_pipelines_path }
          format.json { render :json => stage_json(@stage), :status => :ok }
        end
      else
        render_stage_errors
      end
    rescue ActiveRecord::RecordNotUnique
      @stage.errors.add(:name, :taken)
      render_stage_errors
    end

    def destroy
      @pipeline = @stage.pipeline
      if @stage.destroy
        respond_to do |format|
          format.html { redirect_to crm_pipelines_path }
          format.json { render :json => {:id => @stage.id, :deleted => true}, :status => :ok }
        end
      else
        render_stage_errors
      end
    rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::InvalidForeignKey => e
      @stage.errors.add(:base, e.message)
      render_stage_errors
    end

    private

    def find_stage
      @stage = CrmPipelineStage.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render_404
    end

    def render_stage_errors
      @pipelines = CrmPipeline.includes(:stages).order(:position, :id).to_a
      respond_to do |format|
        format.html { render 'crm/pipelines/index', :status => :unprocessable_content }
        format.json { render :json => {:errors => @stage.errors.full_messages}, :status => :unprocessable_content }
      end
    end

    def stage_json(stage)
      {:id => stage.id, :pipeline_id => stage.pipeline_id, :name => stage.name,
       :position => stage.position, :probability => stage.probability, :kind => stage.kind,
       :color => stage.color, :followup_text => stage.followup_text,
       :followup_due_days => stage.followup_due_days}
    end
  end
end
