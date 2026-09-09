# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'digest'

module RedmineCrm
  # Produces a portable, human-readable JSON snapshot.  The PostgreSQL backup
  # remains the restore artifact; this export is intentionally self-describing
  # and useful when the plugin is not loaded.
  class Export
    SCHEMA_VERSION = 1

    CRM_RECORDS = {
      'accounts' => 'CrmAccount',
      'contacts' => 'CrmContact',
      'deals' => 'CrmDeal',
      'activities' => 'CrmActivity',
      'pipelines' => 'CrmPipeline',
      'pipeline_stages' => 'CrmPipelineStage',
      'links' => 'CrmLink',
      'account_projects' => 'CrmAccountProject',
      'changes' => 'CrmChange'
    }.freeze

    def self.call(dir:, user: nil, redact_money: nil)
      new(:dir => dir, :user => user, :redact_money => redact_money).run!
    end

    def initialize(dir:, user: nil, redact_money: nil)
      @dir = File.expand_path(dir.to_s)
      @user = user || (User.current if defined?(User))
      @redact_money = redact_money.nil? ? !can_view_money? : !!redact_money
      @written = []
    end

    attr_reader :written

    def run!
      raise ArgumentError, 'export directory is required' if @dir.to_s == ''
      FileUtils.mkdir_p(@dir)

      CRM_RECORDS.each do |filename, class_name|
        write_json(filename, class_name, records_for(class_name))
      end
      write_json('custom_fields', 'CustomField', custom_field_records)
      write_json('custom_values', 'CustomValue', custom_value_records)
      write_json('queries', 'Query', query_records)
      write_json('attachments', 'Attachment', attachment_records)
      @written
    end

    private

    def can_view_money?
      return false unless defined?(Crm::Access)
      Crm::Access.can_view_money?(@user || User.current)
    rescue StandardError
      false
    end

    def crm_class(name)
      name.constantize
    rescue NameError
      nil
    end

    def rows_for(class_name)
      klass = crm_class(class_name)
      return [] unless klass
      scope = klass.respond_to?(:unscoped) ? klass.unscoped : klass.all
      scope.to_a
    end

    def records_for(class_name)
      rows_for(class_name).map { |record| serialize_record(record, class_name) }
    end

    def serialize_record(record, class_name)
      hash = record.attributes.each_with_object({}) do |(key, value), result|
        next if @redact_money && class_name == 'CrmDeal' && %w[amount_cents currency weighted_cents].include?(key)
        result[key] = json_value(value)
      end
      hash['external_ref'] = record.external_ref if record.respond_to?(:external_ref) && !hash.key?('external_ref')
      hash['custom_values'] = serialize_record_custom_values(record) if record.respond_to?(:custom_values)
      hash['attachments'] = serialize_record_attachments(record) if record.respond_to?(:attachments)
      hash
    end

    def serialize_record_custom_values(record)
      record.custom_values.filter_map do |custom_value|
        field = custom_value.custom_field
        next unless field_visible?(field)
        {
          'field_id' => field.id,
          'name' => field.name,
          'type' => field.type,
          'value' => json_value(custom_value.value)
        }
      end
    rescue StandardError
      []
    end

    def custom_field_records
      classes = %w[CrmAccountCustomField CrmContactCustomField CrmDealCustomField]
      classes.flat_map do |class_name|
        rows_for(class_name).filter_map do |field|
          next unless field_visible?(field)
          {
            'id' => field.id,
            'type' => field.type,
            'customized_class' => field.respond_to?(:customized_class) ? field.customized_class : nil,
            'name' => field.name,
            'field_format' => field.field_format,
            'possible_values' => json_value(field.possible_values),
            'multiple' => field.respond_to?(:multiple?) ? field.multiple? : false,
            'visible' => field.respond_to?(:visible?) ? field.visible? : true
          }
        end
      end
    end

    def custom_value_records
      rows_for('CustomValue').filter_map do |value|
        field = value.custom_field
        next unless field && field_visible?(field)
        {
          'id' => value.id,
          'custom_field_id' => value.custom_field_id,
          'customized_type' => value.customized_type,
          'customized_id' => value.customized_id,
          'value' => json_value(value.value)
        }
      end
    rescue StandardError
      []
    end

    def query_records
      rows = rows_for('Query')
      rows = rows.select { |query| query.respond_to?(:type) && query.type.to_s.start_with?('Crm') }
      rows.map do |query|
        query.attributes.each_with_object({}) { |(key, value), result| result[key] = json_value(value) }
      end
    end

    def attachment_records
      rows_for('Attachment').filter_map do |attachment|
        next unless crm_attachment?(attachment)
        {
          'id' => attachment.id,
          'container_type' => attachment.container_type,
          'container_id' => attachment.container_id,
          'filename' => attachment.filename,
          'disk_filename' => attachment.disk_filename,
          'filesize' => attachment.filesize,
          'content_type' => attachment.content_type,
          'digest' => attachment_digest(attachment),
          'created_on' => json_value(attachment.respond_to?(:created_on) ? attachment.created_on : attachment.created_at)
        }
      end
    end

    def serialize_record_attachments(record)
      return [] unless record.respond_to?(:attachments)
      record.attachments.map do |attachment|
        {
          'id' => attachment.id,
          'filename' => attachment.filename,
          'filesize' => attachment.filesize,
          'content_type' => attachment.content_type,
          'digest' => attachment_digest(attachment)
        }
      end
    rescue StandardError
      []
    end

    def crm_attachment?(attachment)
      attachment.respond_to?(:container_type) && attachment.container_type.to_s.start_with?('Crm')
    end

    def attachment_digest(attachment)
      path = attachment.respond_to?(:diskfile) ? attachment.diskfile : nil
      return nil unless path && File.file?(path)
      Digest::SHA256.file(path).hexdigest
    rescue StandardError
      nil
    end

    def field_visible?(field)
      return true unless field
      return true if @user && @user.respond_to?(:admin?) && @user.admin?
      field.respond_to?(:visible?) ? field.visible? : true
    end

    def json_value(value)
      return value.map { |item| json_value(item) } if value.is_a?(Array)
      return value.each_with_object({}) { |(key, item), hash| hash[key] = json_value(item) } if value.is_a?(Hash)
      return value.iso8601 if value.respond_to?(:iso8601)
      value
    end

    def write_json(filename, class_name, records)
      payload = {
        'schema_version' => SCHEMA_VERSION,
        'record_type' => class_name,
        'money_redacted' => @redact_money,
        'count' => records.length,
        'completeness' => {'records' => records.length},
        'records' => records
      }
      path = File.join(@dir, "#{filename}.json")
      File.write(path, JSON.pretty_generate(payload) + "\n")
      @written << path
    end
  end
end
