# frozen_string_literal: true

require 'active_support/core_ext/object/blank'

module RedmineCrm
  # Install-time data for the CRM.  This class deliberately uses find-or-create
  # operations rather than fixtures: production installs already contain users,
  # projects and (occasionally) a partially completed CRM setup.
  class Setup
    SOURCE_VALUES = %w[manual twenty-manual twenty-api twenty-email upwork].freeze

    PIPELINE_STAGES = [
      ['New', 'open', 10],
      ['Qualifying', 'open', 20],
      ['Discovery', 'open', 30],
      ['Proposal Sent', 'open', 50],
      ['Negotiation', 'open', 75],
      ['Closed Won', 'won', 100],
      ['Closed Lost', 'lost', 0]
    ].freeze

    CUSTOM_FIELDS = {
      'Account' => [
        ['Industry', 'list', ['Technology', 'E-commerce', 'Healthcare', 'Finance', 'Real Estate']],
        ['Employees', 'int', nil],
        ['Ideal customer', 'bool', nil],
        ['LinkedIn', 'link', nil],
        ['X', 'link', nil],
        ['Source', 'list', SOURCE_VALUES]
      ],
      'Contact' => [
        ['Department', 'list', ['Engineering', 'Operations', 'Sales', 'Marketing', 'Finance', 'Other']],
        ['Stakeholder role', 'list', ['Decision Maker', 'Champion', 'Economic Buyer', 'Technical Buyer']],
        ['Return client', 'bool', nil],
        ['Source', 'list', SOURCE_VALUES]
      ],
      'Deal' => [
        ['Contract type', 'list', ['Fixed Price', 'Hourly', 'Retainer']],
        ['Lead source', 'list', ['Referral', 'Inbound', 'Cold outreach', 'Upwork', 'Other platform']],
        ['Loss reason', 'list', ['No budget', 'Chose competitor', 'No response', 'Wrong scope']],
        ['Loss notes', 'text', nil],
        ['Priority', 'list', ['Hot', 'Warm', 'Cold']],
        ['Service type', 'list', ['Web Application', 'Mobile App', 'E-commerce', 'API Integration']],
        ['First contact', 'date', nil],
        ['Source', 'list', SOURCE_VALUES]
      ]
    }.freeze

    class << self
      def run!
        new.run!
      end

      # The importer calls this narrow helper when an operator ran the import
      # before the separate setup task.  It does not touch groups or fields.
      def seed_pipeline!
        new.seed_pipeline!
      end
    end

    def run!
      ApplicationRecord.transaction do
        seed_groups
        seed_contractor_role
        seed_pipeline
        seed_custom_fields
      end
      true
    end

    def seed_pipeline
      pipeline_class = crm_class('CrmPipeline')
      stage_class = crm_class('CrmPipelineStage')
      raise 'CrmPipeline and CrmPipelineStage must be loaded before CRM setup' unless pipeline_class && stage_class

      # PostgreSQL's partial unique index allows only one default.  Clear old
      # defaults before making Sales the default, including a half-installed
      # setup where Sales already exists.
      pipeline_class.where(:is_default => true).update_all(:is_default => false)
      pipeline = pipeline_class.where(:name => 'Sales').first_or_initialize
      assign(pipeline, :position, 1)
      assign(pipeline, :is_default, true)
      assign_created_on(pipeline)
      pipeline.save!

      PIPELINE_STAGES.each_with_index do |(name, kind, probability), index|
        stage = stage_class.where(:pipeline_id => pipeline.id, :name => name).first_or_initialize
        assign(stage, :pipeline_id, pipeline.id)
        assign(stage, :name, name)
        assign(stage, :position, index + 1)
        assign(stage, :probability, probability)
        assign(stage, :kind, kind)
        assign_created_on(stage)
        stage.save!
      end
      pipeline
    end

    private

    def seed_groups
      %w[GROUP_STAFF GROUP_VIEWER GROUP_FEED].each do |constant_name|
        name = RedmineCrm.const_get(constant_name)
        group = Group.where(:lastname => name).first_or_initialize
        group.lastname = name
        group.save!
      end
    end

    def seed_contractor_role
      role = Role.where(:name => RedmineCrm::CONTRACTOR_ROLE_NAME).first_or_initialize
      assign(role, :name, RedmineCrm::CONTRACTOR_ROLE_NAME)
      assign(role, :builtin, 0)
      assign(role, :assignable, true) if role.respond_to?(:assignable=)
      # This is intentionally a replacement, not add_permission!: the role is
      # required to have exactly one capability even after an old install.
      role.permissions = [:view_crm_linked]
      role.save!
    end

    def seed_custom_fields
      CUSTOM_FIELDS.each do |kind, definitions|
        klass = crm_class("Crm#{kind}CustomField")
        raise "missing #{kind} CRM custom-field class" unless klass

        definitions.each do |name, format, values|
          field = klass.where(:name => name).first_or_initialize
          assign(field, :name, name)
          assign(field, :field_format, format)
          assign(field, :possible_values, values) if values
          assign(field, :multiple, false) if field.respond_to?(:multiple=)
          assign(field, :visible, true) if field.respond_to?(:visible=)
          assign(field, :is_filter, true) if field.respond_to?(:is_filter=)
          assign(field, :is_for_all, true) if field.respond_to?(:is_for_all=)
          # List values should be searchable only when the field format allows
          # it; CustomField#set_searchable applies the core restriction.
          assign(field, :searchable, false) if field.respond_to?(:searchable=)
          field.save!
        end
      end
    end

    def crm_class(name)
      name.constantize
    rescue NameError
      nil
    end

    def assign(record, attribute, value)
      writer = "#{attribute}="
      record.public_send(writer, value) if record.respond_to?(writer)
    end

    def assign_created_on(record)
      assign(record, :created_on, Time.current) if record.respond_to?(:created_on=) && record.created_on.blank?
    end
  end
end
