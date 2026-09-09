# frozen_string_literal: true

# Query support shared by the four global CRM query subclasses.  It lives in
# this file because the plugin deliberately has no second query base model.
module CrmQuerySupport
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def visible(user = User.current)
      return none unless CrmQuerySupport.query_reader?(user)

      where(:project_id => nil).
        where("#{table_name}.visibility = :public OR #{table_name}.user_id = :user_id",
              :public => Query::VISIBILITY_PUBLIC, :user_id => user.id)
    end
  end

  def visible?(user = User.current)
    return false unless self.class.visible(user).where(:id => id).exists?

    project_id.nil?
  end

  def editable_by?(user = User.current)
    CrmQuerySupport.query_manager?(user) && project_id.nil?
  end

  def build_from_params(params, defaults = {})
    self.filters ||= {}
    super
    if params[:include_archived].present?
      add_filter('archived', '*', [''])
    end
    self
  end

  def crm_base_scope
    scope = queried_class.visible(User.current)
    scope = scope.unscope(:where => :archived_on) if crm_archive_filter_present? && scope.respond_to?(:unscope)
    scope = scope.where("#{queried_table_name}.archived_on IS NULL") unless crm_archive_filter_present?
    scope = scope.where(statement) if statement.present?
    scope
  end

  def results_scope(options = {})
    options = options.dup
    order_option = [group_by_sort_order, (options[:order] || sort_clause)].flatten.reject(&:blank?)
    unless order_option.any? {|item| item.to_s.start_with?("#{queried_table_name}.id ")}
      order_option << "#{queried_table_name}.id ASC"
    end

    scope = base_scope.
      where(options[:conditions]).
      order(order_option).
      joins(joins_for_order_statement(order_option.join(','))).
      limit(options[:limit]).
      offset(options[:offset])

    includes = options[:include] || (respond_to?(:crm_query_includes) ? crm_query_includes : [])
    scope = scope.includes(Array(includes).compact.uniq) if includes.present?
    scope
  end

  def results(options = {})
    results_scope(options).to_a
  rescue ::ActiveRecord::StatementInvalid => e
    raise StatementInvalid.new(e.message)
  end

  def result_count
    base_scope.count
  rescue ::ActiveRecord::StatementInvalid => e
    raise StatementInvalid.new(e.message)
  end

  def queried_table_name
    @queried_table_name ||= queried_class.table_name
  end

  def crm_archive_filter_present?
    filters && (filters.key?('archived') || filters.key?(:archived))
  end

  def crm_visible_custom_fields
    klass = "#{queried_class.name}CustomField".safe_constantize
    return [] unless klass

    scope = klass.respond_to?(:visible) ? klass.visible(User.current) : klass.all
    scope.order(:position).to_a
  end

  def crm_filter_custom_fields
    crm_visible_custom_fields.select {|field| field.is_filter? }
  end

  def crm_add_custom_fields_filters
    klass = "#{queried_class.name}CustomField".safe_constantize
    add_custom_fields_filters(klass) if klass
  end

  def crm_add_custom_field_columns(columns)
    columns + crm_visible_custom_fields.map {|field| QueryCustomFieldColumn.new(field) }
  end

  def crm_owner_values
    values = []
    values << ["<< #{l(:label_me)} >>", 'me'] if User.current.logged?
    users = User.where(:status => User::STATUS_ACTIVE).order(:lastname, :firstname, :id)
    values + users.map {|user| [user.name, user.id.to_s] }
  end

  def crm_values(klass, label = :name)
    klass.order(label, :id).pluck(label, :id).map {|name, id| [name.to_s, id.to_s] }
  end

  def crm_label(name)
    l(:"field_crm_#{name}")
  end

  def crm_list_filter(field, values, options = {})
    add_available_filter(field, {
      :type => (options.delete(:type) || :list_optional),
      :values => values,
      :name => (options.delete(:name) || crm_label(field.to_s.sub(/_id\z/, '')))
    }.merge(options))
  end

  def sql_for_archived_field(_field, operator, value)
    table = queried_table_name
    truth = value.map(&:to_s).any? {|item| %w[1 true yes archived].include?(item.downcase) }
    case operator
    when '*'
      '1=1'
    when '!*'
      "#{table}.archived_on IS NULL"
    when '='
      truth ? "#{table}.archived_on IS NOT NULL" : "#{table}.archived_on IS NULL"
    when '!'
      truth ? "#{table}.archived_on IS NULL" : "#{table}.archived_on IS NOT NULL"
    else
      "#{table}.archived_on IS NULL"
    end
  end

  def self.query_reader?(user)
    return false unless user && user.respond_to?(:id)

    %i[admin staff viewer].include?(Crm::Access.capability(user).to_sym)
  rescue StandardError
    false
  end

  def self.query_manager?(user)
    return false unless user && user.respond_to?(:id)

    Crm::Access.can_manage_queries?(user)
  rescue StandardError
    false
  end
end

class CrmAccountQuery < Query
  include CrmQuerySupport

  self.queried_class = CrmAccount
  self.view_permission = :view_crm_linked
  self.available_columns = [
    QueryColumn.new(:id, :sortable => "#{CrmAccount.table_name}.id", :default_order => 'desc',
                    :caption => :field_crm_id, :frozen => true),
    QueryColumn.new(:name, :sortable => "#{CrmAccount.table_name}.name", :groupable => true,
                    :caption => :field_crm_name),
    QueryColumn.new(:domain, :sortable => "#{CrmAccount.table_name}.domain", :caption => :field_crm_domain),
    QueryColumn.new(:status, :sortable => "#{CrmAccount.table_name}.status", :groupable => true,
                    :caption => :field_crm_status),
    QueryColumn.new(:owner, :sortable => lambda { User.fields_for_order_statement }, :groupable => true,
                    :caption => :field_crm_owner),
    QueryColumn.new(:website, :sortable => "#{CrmAccount.table_name}.website", :caption => :field_crm_website),
    QueryColumn.new(:phone, :sortable => "#{CrmAccount.table_name}.phone", :caption => :field_crm_phone),
    QueryColumn.new(:address, :sortable => "#{CrmAccount.table_name}.address", :caption => :field_crm_address),
    TimestampQueryColumn.new(:created_on, :sortable => "#{CrmAccount.table_name}.created_on",
                             :default_order => 'desc', :groupable => true, :caption => :field_crm_created_on),
    TimestampQueryColumn.new(:updated_on, :sortable => "#{CrmAccount.table_name}.updated_on",
                             :default_order => 'desc', :groupable => true, :caption => :field_crm_updated_on),
    TimestampQueryColumn.new(:archived_on, :sortable => "#{CrmAccount.table_name}.archived_on",
                             :default_order => 'desc', :groupable => true, :caption => :field_crm_archived_on)
  ]

  def self.default(project: nil, user: User.current)
    return nil unless project.nil?

    visible(user).where(:visibility => VISIBILITY_PUBLIC).order(:name, :id).first
  end


  def initialize(attributes = nil, *args)
    super(attributes)
    self.filters ||= {}
  end

  def initialize_available_filters
    crm_list_filter('status', lambda {
      %w[lead prospect active_client past_client partner other].map {|value| [value.humanize, value] }
    }, :type => :list)
    crm_list_filter('owner_id', lambda { crm_owner_values })
    add_available_filter('name', :type => :text, :name => crm_label('name'))
    add_available_filter('domain', :type => :string, :name => crm_label('domain'))
    add_available_filter('website', :type => :string, :name => crm_label('website'))
    add_available_filter('phone', :type => :string, :name => crm_label('phone'))
    add_available_filter('address', :type => :text, :name => crm_label('address'))
    add_available_filter('description', :type => :text, :name => crm_label('description'))
    add_available_filter('external_ref', :type => :string, :name => crm_label('external_ref'))
    add_available_filter('project_id', :type => :list_optional,
                         :name => crm_label('project'),
                         :values => lambda { Project.visible.order(:name, :id).pluck(:name, :id).map {|name, id| [name, id.to_s] } })
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
  end

  def default_columns_names
    [:name, :status, :owner, :domain, :updated_on]
  end

  def default_sort_criteria
    [['name', 'asc']]
  end

  def base_scope
    crm_base_scope.left_joins(:owner)
  end

  def crm_query_includes
    [:owner]
  end

  def sql_for_project_id_field(_field, operator, value)
    ids = value.map(&:to_i).join(',')
    any = "EXISTS (SELECT 1 FROM crm_account_projects cap WHERE cap.account_id = #{CrmAccount.table_name}.id)"
    selected = "EXISTS (SELECT 1 FROM crm_account_projects cap WHERE cap.account_id = #{CrmAccount.table_name}.id AND cap.project_id IN (#{ids}))"
    case operator
    when '!' then "NOT (#{selected})"
    when '!*' then "NOT (#{any})"
    else selected
    end
  end
end
