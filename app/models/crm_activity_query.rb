# frozen_string_literal: true

require_relative 'crm_account_query' unless defined?(CrmQuerySupport)

class CrmActivityQuery < Query
  include CrmQuerySupport

  self.queried_class = CrmActivity
  self.view_permission = :view_crm_linked
  self.available_columns = [
    QueryColumn.new(:id, :sortable => "#{CrmActivity.table_name}.id", :default_order => 'desc',
                    :caption => :field_crm_id, :frozen => true),
    QueryColumn.new(:kind, :sortable => "#{CrmActivity.table_name}.kind", :groupable => true,
                    :caption => :field_crm_kind),
    QueryColumn.new(:channel, :sortable => "#{CrmActivity.table_name}.channel", :groupable => true,
                    :caption => :field_crm_channel),
    QueryColumn.new(:direction, :sortable => "#{CrmActivity.table_name}.direction", :groupable => true,
                    :caption => :field_crm_direction),
    QueryColumn.new(:subject, :sortable => "#{CrmActivity.table_name}.subject", :caption => :field_crm_subject),
    QueryColumn.new(:body, :inline => false, :caption => :field_crm_body),
    TimestampQueryColumn.new(:occurred_at, :sortable => "#{CrmActivity.table_name}.occurred_at",
                             :default_order => 'desc', :groupable => true, :caption => :field_crm_occurred_at),
    QueryColumn.new(:duration_minutes, :sortable => "#{CrmActivity.table_name}.duration_minutes",
                    :caption => :field_crm_duration_minutes),
    QueryAssociationColumn.new(:account, :name, :sortable => "#{CrmAccount.table_name}.name",
                               :groupable => true, :caption => :field_crm_account),
    QueryAssociationColumn.new(:contact, :last_name, :sortable => "#{CrmContact.table_name}.last_name",
                               :groupable => true, :caption => :field_crm_contact),
    QueryAssociationColumn.new(:deal, :name, :sortable => "#{CrmDeal.table_name}.name",
                               :groupable => true, :caption => :field_crm_deal),
    QueryColumn.new(:author, :sortable => lambda { User.fields_for_order_statement }, :groupable => true,
                    :caption => :field_crm_author),
    QueryColumn.new(:visibility, :sortable => "#{CrmActivity.table_name}.visibility", :groupable => true,
                    :caption => :field_crm_visibility),
    TimestampQueryColumn.new(:created_on, :sortable => "#{CrmActivity.table_name}.created_on",
                             :default_order => 'desc', :groupable => true, :caption => :field_crm_created_on),
    TimestampQueryColumn.new(:updated_on, :sortable => "#{CrmActivity.table_name}.updated_on",
                             :default_order => 'desc', :groupable => true, :caption => :field_crm_updated_on),
    TimestampQueryColumn.new(:archived_on, :sortable => "#{CrmActivity.table_name}.archived_on",
                             :default_order => 'desc', :groupable => true, :caption => :field_crm_archived_on)
  ]

  def self.default(project: nil, user: User.current)
    return nil unless project.nil?

    visible(user).where(:visibility => VISIBILITY_PUBLIC).order(:id).first
  end


  def initialize(attributes = nil, *args)
    super(attributes)
    self.filters ||= {}
  end

  def initialize_available_filters
    crm_list_filter('kind', lambda {
      %w[note call meeting message other].map {|value| [value.humanize, value] }
    }, :type => :list, :name => crm_label('kind'))
    crm_list_filter('channel', lambda {
      %w[upwork email phone sms in_person other].map {|value| [value.humanize, value] }
    }, :type => :list_optional, :name => crm_label('channel'))
    crm_list_filter('direction', lambda {
      %w[inbound outbound].map {|value| [value.humanize, value] }
    }, :type => :list_optional, :name => crm_label('direction'))
    crm_list_filter('visibility', lambda {
      %w[staff shared].map {|value| [value.humanize, value] }
    }, :type => :list, :name => crm_label('visibility'))
    crm_list_filter('account_id', lambda { crm_values(CrmAccount) }, :name => crm_label('account'))
    add_available_filter('account.name', :type => :string, :name => crm_label('account'))
    crm_list_filter('contact_id', lambda { crm_values(CrmContact) }, :name => crm_label('contact'))
    crm_list_filter('deal_id', lambda { crm_values(CrmDeal) }, :name => crm_label('deal'))
    crm_list_filter('author_id', lambda { crm_owner_values }, :name => crm_label('author'))
    add_available_filter('subject', :type => :text, :name => crm_label('subject'))
    add_available_filter('body', :type => :text, :name => crm_label('body'))
    add_available_filter('occurred_at', :type => :date, :name => crm_label('occurred_at'))
    add_available_filter('duration_minutes', :type => :integer, :name => crm_label('duration_minutes'))
    add_available_filter('external_source', :type => :string, :name => crm_label('external_source'))
    add_available_filter('external_id', :type => :string, :name => crm_label('external_id'))
    add_available_filter('created_on', :type => :date_past, :name => crm_label('created_on'))
    add_available_filter('updated_on', :type => :date_past, :name => crm_label('updated_on'))
    add_available_filter('archived', :type => :list_optional,
                         :name => crm_label('archived'),
                         :values => [[l(:general_text_yes), '1'], [l(:general_text_no), '0']])
  end

  def available_columns
    @available_columns ||= self.class.available_columns.dup
  end

  def default_columns_names
    [:kind, :subject, :occurred_at, :account, :contact, :deal, :author]
  end

  def default_sort_criteria
    [['occurred_at', 'desc'], ['id', 'desc']]
  end

  def base_scope
    crm_base_scope.left_joins(:account, :contact, :deal, :author)
  end

  def crm_query_includes
    [:account, :contact, :deal, :author]
  end

  def sql_for_account_id_field(_field, operator, value)
    ids = value.map(&:to_i).uniq
    return '1=0' if ids.empty? && operator == '='

    id_list = ids.join(',')
    account_table = CrmAccount.table_name
    contact_table = CrmContact.table_name
    deal_table = CrmDeal.table_name
    activity_table = CrmActivity.table_name
    condition = <<~SQL.squish
      (#{activity_table}.account_id IN (#{id_list})
       OR #{activity_table}.contact_id IN (SELECT id FROM #{contact_table} WHERE account_id IN (#{id_list}))
       OR #{activity_table}.deal_id IN (SELECT id FROM #{deal_table} WHERE account_id IN (#{id_list})))
    SQL
    case operator
    when '!' then "NOT (#{condition})"
    when '*' then "(#{activity_table}.account_id IS NOT NULL OR #{activity_table}.contact_id IS NOT NULL OR #{activity_table}.deal_id IS NOT NULL)"
    when '!*' then "#{activity_table}.account_id IS NULL AND #{activity_table}.contact_id IS NULL AND #{activity_table}.deal_id IS NULL"
    else condition
    end
  end

  def sql_for_account_name_field(_field, operator, value)
    account_table = CrmAccount.table_name
    contact_table = CrmContact.table_name
    deal_table = CrmDeal.table_name
    activity_table = CrmActivity.table_name
    account_condition = sql_for_field('name', operator, value, 'a', 'name')
    contact_condition = sql_for_field('name', operator, value, 'ca', 'name')
    deal_condition = sql_for_field('name', operator, value, 'da', 'name')
    "(EXISTS (SELECT 1 FROM #{account_table} a WHERE a.id = #{activity_table}.account_id AND (#{account_condition})) " \
      "OR EXISTS (SELECT 1 FROM #{contact_table} c INNER JOIN #{account_table} ca ON ca.id = c.account_id " \
      "WHERE c.id = #{activity_table}.contact_id AND (#{contact_condition})) " \
      "OR EXISTS (SELECT 1 FROM #{deal_table} d INNER JOIN #{account_table} da ON da.id = d.account_id " \
      "WHERE d.id = #{activity_table}.deal_id AND (#{deal_condition})))"
  end
end
