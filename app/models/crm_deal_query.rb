# frozen_string_literal: true

require_relative 'crm_account_query' unless defined?(CrmQuerySupport)

class CrmDealQuery < Query
  include CrmQuerySupport

  self.queried_class = CrmDeal
  self.view_permission = :view_crm_linked
  self.available_columns = [
    QueryColumn.new(:id, :sortable => "#{CrmDeal.table_name}.id", :default_order => 'desc',
                    :caption => :field_crm_id, :frozen => true),
    QueryColumn.new(:name, :sortable => "#{CrmDeal.table_name}.name", :groupable => true,
                    :caption => :field_crm_name),
    CrmAssociationQueryColumn.new(:account, :name, :sortable => "#{CrmAccount.table_name}.name",
                                  :groupable => true, :caption => :field_crm_account),
    CrmAssociationQueryColumn.new(:contact, :last_name, :sortable => "#{CrmContact.table_name}.last_name",
                                  :groupable => true, :caption => :field_crm_contact),
    CrmAssociationQueryColumn.new(:pipeline, :name, :sortable => "#{CrmPipeline.table_name}.name",
                                  :groupable => true, :caption => :field_crm_pipeline),
    CrmAssociationQueryColumn.new(:stage, :name, :sortable => "#{CrmPipelineStage.table_name}.name",
                                  :groupable => true, :caption => :field_crm_stage),
    CrmAssociationQueryColumn.new(:stage, :kind, :column_name => :status,
                                  :sortable => "#{CrmPipelineStage.table_name}.kind",
                                  :groupable => true, :caption => :field_crm_status),
    QueryColumn.new(:probability, :sortable => "#{CrmDeal.table_name}.probability", :groupable => true,
                    :caption => :field_crm_probability),
    QueryColumn.new(:owner, :sortable => lambda { User.fields_for_order_statement }, :groupable => true,
                    :caption => :field_crm_owner),
    TimestampQueryColumn.new(:expected_close_on, :sortable => "#{CrmDeal.table_name}.expected_close_on",
                             :groupable => true, :caption => :field_crm_expected_close_on),
    TimestampQueryColumn.new(:closed_on, :sortable => "#{CrmDeal.table_name}.closed_on",
                             :groupable => true, :caption => :field_crm_closed_on),
    QueryColumn.new(:next_action, :sortable => "#{CrmDeal.table_name}.next_action",
                    :caption => :field_crm_next_action),
    TimestampQueryColumn.new(:next_action_on, :sortable => "#{CrmDeal.table_name}.next_action_on",
                             :groupable => true, :caption => :field_crm_next_action_on),
    TimestampQueryColumn.new(:created_on, :sortable => "#{CrmDeal.table_name}.created_on",
                             :default_order => 'desc', :groupable => true, :caption => :field_crm_created_on),
    TimestampQueryColumn.new(:updated_on, :sortable => "#{CrmDeal.table_name}.updated_on",
                             :default_order => 'desc', :groupable => true, :caption => :field_crm_updated_on),
    TimestampQueryColumn.new(:archived_on, :sortable => "#{CrmDeal.table_name}.archived_on",
                             :default_order => 'desc', :groupable => true, :caption => :field_crm_archived_on)
  ]

  def self.default(project: nil, user: User.current)
    return nil unless project.nil?

    visible(user).where(:visibility => VISIBILITY_PUBLIC).order(:name, :id).first
  end

  def initialize(attributes = nil, *args)
    super(attributes)
    self.filters ||= {
      'status' => {:operator => '=', :values => ['open']}
    }
  end

  def initialize_available_filters
    crm_list_filter('status', lambda {
      %w[open won lost].map {|value| [value.humanize, value] }
    }, :type => :list_status, :name => crm_label('status'))
    crm_list_filter('pipeline_id', lambda { crm_values(CrmPipeline) }, :type => :list,
                    :name => crm_label('pipeline'))
    crm_list_filter('stage_id', lambda { crm_values(CrmPipelineStage) }, :type => :list,
                    :name => crm_label('stage'))
    add_available_filter('pipeline.name', :type => :string, :name => crm_label('pipeline'))
    crm_list_filter('account_id', lambda { crm_values(CrmAccount) }, :name => crm_label('account'))
    add_available_filter('account.name', :type => :string, :name => crm_label('account'))
    crm_list_filter('contact_id', lambda { crm_values(CrmContact) }, :name => crm_label('contact'))
    crm_list_filter('owner_id', lambda { crm_owner_values }, :name => crm_label('owner'))
    add_available_filter('name', :type => :text, :name => crm_label('name'))
    add_available_filter('description', :type => :text, :name => crm_label('description'))
    add_available_filter('external_ref', :type => :string, :name => crm_label('external_ref'))
    add_available_filter('probability', :type => :integer, :name => crm_label('probability'))
    add_available_filter('expected_close_on', :type => :date, :name => crm_label('expected_close_on'))
    add_available_filter('closed_on', :type => :date_past, :name => crm_label('closed_on'))
    add_available_filter('next_action', :type => :string, :name => crm_label('next_action'))
    add_available_filter('next_action_on', :type => :date, :name => crm_label('next_action_on'))
    add_available_filter('created_on', :type => :date_past, :name => crm_label('created_on'))
    add_available_filter('updated_on', :type => :date_past, :name => crm_label('updated_on'))
    add_available_filter('archived', :type => :list_optional,
                         :name => crm_label('archived'),
                         :values => [[l(:general_text_yes), '1'], [l(:general_text_no), '0']])
    crm_add_custom_fields_filters
  end

  def available_columns
    return @available_columns if @available_columns

    @available_columns = crm_add_custom_field_columns(self.class.available_columns.dup)
    if Crm::Access.can_view_money?(User.current)
      weighted_sql = crm_weighted_sql
      @available_columns.concat([
        QueryColumn.new(:amount_cents, :sortable => "#{CrmDeal.table_name}.amount_cents",
                        :totalable => true, :caption => :field_crm_amount),
        QueryColumn.new(:currency, :sortable => "#{CrmDeal.table_name}.currency", :groupable => true,
                        :caption => :field_crm_currency),
        QueryColumn.new(:weighted_cents, :sortable => weighted_sql, :totalable => true,
                        :caption => :field_crm_weighted_amount)
      ])
    end
    @available_columns
  end

  def default_columns_names
    columns = [:name, :account, :stage, :owner, :next_action_on, :updated_on]
    columns << :amount_cents if Crm::Access.can_view_money?(User.current)
    columns
  end

  def default_totalable_names
    if Crm::Access.can_view_money?(User.current)
      [:amount_cents, :weighted_cents]
    else
      []
    end
  end

  def default_sort_criteria
    [['updated_on', 'desc'], ['id', 'desc']]
  end



  def base_scope
    crm_base_scope.joins(:stage, :pipeline).left_joins(:account, :contact, :owner)
  end

  def crm_query_includes
    [:account, :contact, :pipeline, :stage, :owner]
  end

  def total_for_amount_cents(scope)
    scope.group(:currency).sum(:amount_cents).transform_values {|value| value.to_i }
  end

  def total_for_weighted_cents(scope)
    scope.group(:currency).sum(crm_weighted_sql).transform_values {|value| value.to_i }
  end

  def sql_for_status_field(_field, operator, value)
    sql_for_field('kind', operator, value, CrmPipelineStage.table_name, 'kind')
  end

  def sql_for_pipeline_name_field(_field, operator, value)
    condition = sql_for_field('name', operator, value, CrmPipeline.table_name, 'name')
    "EXISTS (SELECT 1 FROM #{CrmPipeline.table_name} WHERE #{CrmPipeline.table_name}.id = #{CrmDeal.table_name}.pipeline_id AND (#{condition}))"
  end

  def sql_for_account_name_field(_field, operator, value)
    condition = sql_for_field('name', operator, value, CrmAccount.table_name, 'name')
    "EXISTS (SELECT 1 FROM #{CrmAccount.table_name} WHERE #{CrmAccount.table_name}.id = #{CrmDeal.table_name}.account_id AND (#{condition}))"
  end

  def crm_weighted_sql
    "#{CrmDeal.table_name}.amount_cents * COALESCE(#{CrmDeal.table_name}.probability, #{CrmPipelineStage.table_name}.probability) / 100.0"
  end
end
