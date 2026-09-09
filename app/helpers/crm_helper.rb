# frozen_string_literal: true

module CrmHelper
  include CrmFieldsHelper
  def crm_money(cents, currency)
    return '' if cents.nil?

    number_to_currency(cents.to_i / 100.0,
                       :unit => currency.to_s.upcase.presence || 'USD',
                       :format => '%u %n',
                       :precision => 2)
  end
  # Render imported CRM enum values through the locale when one exists.  The
  # optional namespace lets list cells prefer a more specific key while the
  # one-argument form remains suitable for generic imported values such as
  # FOLLOW_UP.
  def crm_humanize_enum(value, namespace = nil)
    text = value.to_s.strip
    return '' if text.blank?

    token = text.underscore
    keys = []
    keys << :"label_crm_#{namespace}_#{token}" if namespace.present?
    keys.concat([
      :"label_crm_#{token}",
      :"label_crm_status_#{token}",
      :"label_crm_activity_#{token}",
      :"label_crm_channel_#{token}",
      :"label_crm_direction_#{token}",
      :"label_crm_visibility_#{token}",
      :"label_crm_stage_kind_#{token}"
    ])

    key = keys.detect {|candidate| I18n.exists?(candidate, I18n.locale) }
    key ? l(key) : text.humanize
  end



  def crm_owner_name(user_id)
    user = user_id.present? ? User.find_by(:id => user_id) : nil
    return user.name.to_s if user && user.name.present?

    l(:label_deleted_user, :default => 'deleted user')
  end

  def crm_record_link(record)
    return ''.html_safe unless record

    path = case record.class.name
           when 'CrmAccount' then crm_account_path(record)
           when 'CrmContact' then crm_contact_path(record)
           when 'CrmDeal' then crm_deal_path(record)
           when 'CrmActivity' then crm_activity_path(record)
           else nil
           end
    return ERB::Util.html_escape(record.to_s) unless path

    label = if record.respond_to?(:name) && record.name.present?
              record.name
            elsif record.respond_to?(:first_name) || record.respond_to?(:last_name)
              [record.try(:first_name), record.try(:last_name)].compact.join(' ').presence || "##{record.id}"
            else
              "##{record.id}"
            end
    link_to label, path
  end

  def crm_capability
    Crm::Access.capability(User.current)
  end

  def crm_visible_custom_values(record, user = User.current)
    return [] unless record.respond_to?(:custom_field_values)

    admin = user.respond_to?(:admin?) && user.admin?
    Array(record.custom_field_values).select do |value|
      field = value.respond_to?(:custom_field) ? value.custom_field : nil
      admin || (field && (!field.respond_to?(:visible?) || field.visible?))
    end
  end

  def crm_history_rows(record, user = User.current)
    return [] unless record && record.respond_to?(:id) && record.id
    return [] unless defined?(CrmChange)

    changes = CrmChange.where(:record_type => record.class.name, :record_id => record.id).order(:created_on, :id)
    admin = user.respond_to?(:admin?) && user.admin?
    money_reader = Crm::Access.can_view_money?(user)

    changes.each_with_object([]) do |change, rows|
      key = change.prop_key.to_s
      field = nil
      if key.start_with?('cf_')
        field_id = key.delete_prefix('cf_').to_i
        field = CustomField.find_by(:id => field_id) if defined?(CustomField)
        # A deleted custom-field definition is history only for administrators.
        next if !admin && (!field || !field.visible?)
      end

      redacted = !money_reader && crm_money_history_key?(key)
      rows << {
        :id => change.id,
        :prop_key => key,
        :name => crm_history_property_name(key, field),
        :old_value => redacted ? nil : change.old_value,
        :value => redacted ? nil : change.value,
        :redacted => redacted,
        :at => change.created_on,
        :user_id => change.user_id,
        :user => crm_owner_name(change.user_id)
      }
    end
  end

  def crm_history_property_name(prop_key, field = nil)
    key = prop_key.to_s
    if key.start_with?('cf_')
      field ||= CustomField.find_by(:id => key.delete_prefix('cf_').to_i) if defined?(CustomField)
      return field.name.to_s if field && field.name.present?
      return l(:label_crm_deleted_field, :default => 'deleted field')
    end

    l("field_crm_#{key}", :default => key.humanize)
  end
  def crm_column_content(column, record)
    column_name = column.name.to_s
    value = column.value_object(record)

    case column_name
    when 'amount_cents'
      value.nil? ? '' : crm_money(value, record.respond_to?(:currency) ? record.currency : nil)
    when 'weighted_cents'
      value.nil? ? '' : crm_money(value, record.respond_to?(:currency) ? record.currency : nil)
    when 'currency'
      value.to_s.upcase.presence || ''
    when 'status'
      namespace = record.is_a?(CrmAccount) ? :account_status : :stage_kind
      crm_humanize_enum(value, namespace)
    when 'kind'
      record.is_a?(CrmActivity) ? crm_humanize_enum(value, :activity_kind) : crm_humanize_enum(value, :stage_kind)
    when 'channel'
      crm_humanize_enum(value, :activity_channel)
    when 'direction'
      crm_humanize_enum(value, :activity_direction)
    when 'visibility'
      crm_humanize_enum(value, :activity_visibility)
    when 'next_action'
      crm_humanize_enum(value)
    when 'contact'
      associated = record.respond_to?(:contact) ? record.contact : nil
      associated ? crm_record_link(associated) : ''
    else
      if column_name == 'name' && value.present?
        crm_record_link(record)
      elsif column_name == 'subject' && value.present? && record.is_a?(CrmActivity)
        link_to value, crm_activity_path(record)
      else
        column_content(column, record)
      end
    end
  end

  def crm_money_total(value)
    return '' if value.nil?

    if value.is_a?(Hash)
      value.sort_by {|currency, _| currency.to_s }.map do |currency, cents|
        crm_money(cents, currency)
      end.join(', ')
    else
      crm_money(value, 'USD')
    end
  end

  # Core's total_tag uses format_object, which intentionally renders a Hash as
  # Ruby syntax. CRM money totals are grouped by currency, so render each
  # currency independently instead.
  def total_tag(column, value)
    return super unless %w[amount_cents weighted_cents].include?(column.name.to_s)

    label = content_tag('span', "#{column.caption}:")
    value_tag = content_tag('span', crm_money_total(value), :class => 'value')
    content_tag('span', label + ' ' + value_tag,
                :class => "total-for-#{column.name.to_s.dasherize}")
  end


 


  def crm_grouped_list(records, query)
    rows = Array(records)
    group_column = query.group_by_column if query && query.respond_to?(:group_by_column) && query.grouped?
    if group_column.nil? && query && params[:group_by].present? && query.respond_to?(:available_columns)
      requested_group = params[:group_by].to_s
      group_column = query.available_columns.find do |column|
        column.name.to_s == requested_group &&
          (!column.respond_to?(:groupable?) || column.groupable?)
      end
    end

    unless group_column
      rows.each {|record| yield record, 0, nil, nil, nil }
      return
    end

    rows = rows.sort_by do |record|
      value = group_column.group_value(record)
      [value.nil? ? 1 : 0, value.to_s]
    end
    counts = begin
      query.result_count_by_group || {}
    rescue StandardError
      {}
    end
    totals = begin
      query.totalable_columns.index_with do |column|
        query.total_by_group_for(column) || {}
      end
    rescue StandardError
      {}
    end
    first = true
    previous_group = nil

    rows.each do |record|
      group = group_column.group_value(record)
      group_name = group_count = group_totals = nil
      if first || group != previous_group
        group_name = if group.blank? && group != false
                       "(#{l(:label_blank_value)})"
                     elsif %w[status kind channel direction visibility].include?(group_column.name.to_s)
                       namespace = if group_column.name.to_s == 'status'
                                     record.is_a?(CrmAccount) ? :account_status : :stage_kind
                                   else
                                     "activity_#{group_column.name}"
                                   end
                       crm_humanize_enum(group, namespace)
                     elsif respond_to?(:format_object)
                       format_object(group)
                     else
                       ERB::Util.html_escape(group.to_s)
                     end
        group_count = counts[group] if counts.respond_to?(:[])
        group_totals = totals.map do |column, values|
          total_tag(column, crm_group_total(values, group, group_column))
        end.join(' ').html_safe

      end
      yield record, 0, group_name, group_count, group_totals
      previous_group = group
      first = false
    end
  end

  def crm_group_total(values, group, group_column = nil)
    return 0 unless values.respond_to?(:each)
    if values.respond_to?(:key?) && values.key?(group)
      return {group => values[group]} if group_column && group_column.name.to_s == 'currency'

      return values[group]
    end

    grouped = {}
    values.each do |key, amount|
      key_group, currency = if key.is_a?(Array)
                              [key.first, key.last]
                            else
                              [key, nil]
                            end
      next unless key_group == group

      if currency.present?
        grouped[currency] = grouped.fetch(currency, 0).to_i + amount.to_i
      else
        return amount
      end
    end
    grouped.presence || 0
  end

  private

  def crm_money_history_key?(key)
    key = key.to_s
    %w[amount amount_cents currency weighted_cents weighted_amount open_cents weighted_total revenue total].include?(key) ||
      key.include?('amount') || key.include?('weighted') || key.include?('revenue')
  end
end
