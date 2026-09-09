# frozen_string_literal: true

require_relative 'crm_account_query' unless defined?(CrmQuerySupport)

class CrmContactQuery < Query
  include CrmQuerySupport

  self.queried_class = CrmContact
  self.view_permission = :view_crm_linked
  self.available_columns = [
    QueryColumn.new(:id, :sortable => "#{CrmContact.table_name}.id", :default_order => 'desc',
                    :caption => :field_crm_id, :frozen => true),
    CrmContactNameQueryColumn.new(:sortable => "#{CrmContact.table_name}.last_name, #{CrmContact.table_name}.first_name",
                                 :caption => :field_crm_name),
    QueryColumn.new(:first_name, :sortable => "#{CrmContact.table_name}.first_name", :groupable => true,
                    :caption => :field_crm_first_name),
    QueryColumn.new(:last_name, :sortable => "#{CrmContact.table_name}.last_name", :default_order => 'asc',
                    :groupable => true, :caption => :field_crm_last_name),
    CrmAssociationQueryColumn.new(:account, :name, :sortable => "#{CrmAccount.table_name}.name",
                                  :groupable => true, :caption => :field_crm_account),
    QueryColumn.new(:email, :sortable => "#{CrmContact.table_name}.email", :caption => :field_crm_email),
    QueryColumn.new(:phone, :sortable => "#{CrmContact.table_name}.phone", :caption => :field_crm_phone),
    QueryColumn.new(:job_title, :sortable => "#{CrmContact.table_name}.job_title", :caption => :field_crm_job_title),
    QueryColumn.new(:city, :sortable => "#{CrmContact.table_name}.city", :groupable => true,
                    :caption => :field_crm_city),
    QueryColumn.new(:owner, :sortable => lambda { User.fields_for_order_statement }, :groupable => true,
                    :caption => :field_crm_owner),
    TimestampQueryColumn.new(:created_on, :sortable => "#{CrmContact.table_name}.created_on",
                             :default_order => 'desc', :groupable => true, :caption => :field_crm_created_on),
    TimestampQueryColumn.new(:updated_on, :sortable => "#{CrmContact.table_name}.updated_on",
                             :default_order => 'desc', :groupable => true, :caption => :field_crm_updated_on),
    TimestampQueryColumn.new(:archived_on, :sortable => "#{CrmContact.table_name}.archived_on",
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
    crm_list_filter('owner_id', lambda { crm_owner_values })
    crm_list_filter('account_id', lambda { crm_values(CrmAccount) }, :type => :list_optional,
                    :name => crm_label('account'))
    add_available_filter('account.name', :type => :string, :name => crm_label('account'))
    add_available_filter('first_name', :type => :string, :name => crm_label('first_name'))
    add_available_filter('last_name', :type => :string, :name => crm_label('last_name'))
    add_available_filter('email', :type => :string, :name => crm_label('email'))
    add_available_filter('phone', :type => :string, :name => crm_label('phone'))
    add_available_filter('job_title', :type => :string, :name => crm_label('job_title'))
    add_available_filter('city', :type => :string, :name => crm_label('city'))
    add_available_filter('linkedin_url', :type => :string, :name => crm_label('linkedin_url'))
    add_available_filter('x_url', :type => :string, :name => crm_label('x_url'))
    add_available_filter('external_ref', :type => :string, :name => crm_label('external_ref'))
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
    [:name, :account, :email, :owner, :updated_on]
  end

  def default_sort_criteria
    [['last_name', 'asc'], ['first_name', 'asc']]
  end

  def base_scope
    crm_base_scope.left_joins(:account, :owner)
  end

  def crm_query_includes
    [:account, :owner]
  end

  def sql_for_account_name_field(_field, operator, value)
    condition = sql_for_field('name', operator, value, CrmAccount.table_name, 'name')
    "EXISTS (SELECT 1 FROM #{CrmAccount.table_name} WHERE #{CrmAccount.table_name}.id = #{CrmContact.table_name}.account_id AND (#{condition}))"
  end
end
