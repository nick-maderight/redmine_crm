# frozen_string_literal: true

module Crm
  class HealthController < BaseController
    before_action :require_login
    before_action :require_health_access
    accept_api_auth :show

    def show
      @health = health_payload
      respond_to do |format|
        format.html { render :show }
        format.api { render :show }
        format.json { render :json => @health }
      end
    end

    private

    def require_health_access
      return if User.current.admin? || Crm::Access.staff?(User.current)

      head :forbidden
    end

    def health_payload
      settings = (Setting.plugin_redmine_crm || {}).stringify_keys
      latest = CrmActivity.where(:external_source => 'upwork').maximum(:created_on)
      freshness_seconds = latest ? (Time.current - latest).to_i : nil
      groups = [RedmineCrm::GROUP_STAFF, RedmineCrm::GROUP_VIEWER, RedmineCrm::GROUP_FEED].each_with_object({}) do |name, result|
        result[name] = Group.exists?(:lastname => name)
      end
      pipeline = CrmPipeline.where(:is_default => true).order(:id).first
      first_open_stage = pipeline && pipeline.stages.where(:kind => 'open').order(:position, :id).first
      schema_version = crm_schema_version
      counts = {
        :accounts => CrmAccount.count,
        :contacts => CrmContact.count,
        :deals => CrmDeal.count,
        :activities => CrmActivity.count,
        :pipelines => CrmPipeline.count,
        :stages => CrmPipelineStage.count
      }
      {
        :schema_version => schema_version,
        :migration_version => schema_version,
        :asset_state => 'ready',
        :readiness => {
          :groups => groups.values.all?,
          :default_pipeline => !pipeline.nil?,
          :first_open_stage => !first_open_stage.nil?
        },
        :counts => counts,
        :latest_upwork_activity_at => latest,
        :upwork_activity_age_seconds => freshness_seconds,
        :freshness => latest.nil? ? 'not_configured' : (freshness_seconds <= 3600 ? 'fresh' : 'stale'),
        :contract_version => settings['feed_contract_version'],
        :feed_last_success_at => settings['feed_last_success_at'],
        :required_groups => groups,
        :default_pipeline => pipeline && {
          :id => pipeline.id,
          :name => pipeline.name,
          :present => true,
          :first_open_stage => first_open_stage && {
            :id => first_open_stage.id,
            :name => first_open_stage.name,
            :kind => first_open_stage.kind,
            :present => true
          }
        }
      }
    end

    def crm_schema_version
      files = Dir.glob(Rails.root.join('plugins', 'redmine_crm', 'db', 'migrate', '*.rb').to_s)
      versions = files.filter_map { |file| File.basename(file)[/\A(\d+)_/, 1] }
      applied = if ActiveRecord::Base.connection.data_source_exists?('schema_migrations')
                  ActiveRecord::Base.connection.select_values('SELECT version FROM schema_migrations')
                else
                  []
                end
      versions.select { |version| applied.include?(version) }.max || versions.max || '0'
    rescue StandardError
      '0'
    end
  end
end
