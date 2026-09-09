# frozen_string_literal: true

# Redmine's issue details use a small row builder to produce the familiar
# split two-column attributes block. CRM records are not Issues, so keep the
# same markup in a plugin helper rather than teaching core about CRM classes.
module CrmFieldsHelper
  class CrmFieldsRows
    include ActionView::Helpers::TagHelper

    def initialize
      @left = []
      @right = []
    end

    def left(*args)
      args.any? ? @left << cells(*args) : @left
    end

    def right(*args)
      args.any? ? @right << cells(*args) : @right
    end

    def size
      [@left.size, @right.size].max
    end

    def to_html
      content =
        content_tag('div', @left.reduce(&:+), :class => 'splitcontentleft') +
        content_tag('div', @right.reduce(&:+), :class => 'splitcontentright')
      content_tag('div', content, :class => 'splitcontent')
    end

    def cells(label, text, options = {})
      options[:class] = [options[:class] || '', 'attribute'].join(' ')
      content_tag(
        'div',
        content_tag('div', label.to_s + ':', :class => 'label') +
          content_tag('div', text, :class => 'value'),
        options
      )
    end
  end

  def crm_fields_rows
    rows = CrmFieldsRows.new
    yield rows
    rows.to_html
  end

  # IssuesHelper exposes these methods, but CRM controllers intentionally do
  # not include the whole issues helper. Keep the custom-field rendering
  # contract and its Redmine markup local to the CRM helper.
  def render_half_width_custom_fields_rows(record)
    values = record.visible_custom_field_values.reject {|value| value.custom_field.full_width_layout? }
    return if values.empty?

    half = (values.size / 2.0).ceil
    crm_fields_rows do |rows|
      values.each_with_index do |value, index|
        side = index < half ? :left : :right
        rows.public_send(
          side,
          custom_field_name_tag(value.custom_field),
          custom_field_value_tag(value),
          :class => value.custom_field.css_classes
        )
      end
    end
  end

  def render_full_width_custom_fields_rows(record)
    values = record.visible_custom_field_values.select {|value| value.custom_field.full_width_layout? }
    return if values.empty?

    values.each_with_object(''.html_safe) do |value, output|
      value_tag = custom_field_value_tag(value)
      next if value_tag.blank?

      content =
        content_tag('hr') +
        content_tag('p', content_tag('strong', custom_field_name_tag(value.custom_field))) +
        content_tag('div', value_tag, :class => 'value')
      output << content_tag('div', content, :class => "#{value.custom_field.css_classes} attribute")
    end
  end
  def crm_history_display_value(prop_key, value)
    return value if value.blank?

    key = prop_key.to_s
    cache = (@crm_history_display_values ||= {})
    cache[[key, value.to_s]] ||= begin
      klass = case key
              when 'stage', 'stage_id' then defined?(CrmPipelineStage) ? CrmPipelineStage : nil
              when 'pipeline', 'pipeline_id' then defined?(CrmPipeline) ? CrmPipeline : nil
              when 'account', 'account_id' then defined?(CrmAccount) ? CrmAccount : nil
              when 'contact', 'contact_id' then defined?(CrmContact) ? CrmContact : nil
              when 'deal', 'deal_id' then defined?(CrmDeal) ? CrmDeal : nil
              when 'owner', 'owner_id' then defined?(User) ? User : nil
              end
      record = klass&.find_by(:id => value)
      if record
        if klass == User
          record.name.to_s.presence || l(:label_deleted_user, :default => 'deleted user')
        elsif record.respond_to?(:name) && record.name.present?
          record.name
        elsif record.respond_to?(:first_name) || record.respond_to?(:last_name)
          [record.try(:first_name), record.try(:last_name)].compact.join(' ').presence || value
        else
          record.to_s
        end
      else
        value
      end
    end
  end

end
