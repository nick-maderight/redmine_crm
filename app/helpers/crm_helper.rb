# frozen_string_literal: true

module CrmHelper
  def crm_money(cents, currency)
    return '' if cents.nil?

    number_to_currency(cents.to_i / 100.0,
                       :unit => currency.to_s.upcase.presence || 'USD',
                       :format => '%u %n',
                       :precision => 2)
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
        :old_value => redacted ? nil : change.old_value,
        :value => redacted ? nil : change.value,
        :redacted => redacted,
        :at => change.created_on,
        :user_id => change.user_id,
        :user => crm_owner_name(change.user_id)
      }
    end
  end

  private

  def crm_money_history_key?(key)
    key = key.to_s
    %w[amount amount_cents currency weighted_cents weighted_amount open_cents weighted_total revenue total].include?(key) ||
      key.include?('amount') || key.include?('weighted') || key.include?('revenue')
  end
end
