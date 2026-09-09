# frozen_string_literal: true

module Crm
  # Shared authorization, visibility and mutation behavior for the CRM's globally
  # scoped records.  CRM controllers deliberately do not use Redmine's project
  # authorization callbacks: Crm::Access and each model's visible scope are the
  # authorization boundary.
  class BaseController < ApplicationController
    menu_item :crm
    helper :queries
    include QueriesHelper
    helper :custom_fields
    include CustomFieldsHelper
    helper :attachments
    helper :sort
    include SortHelper
    helper :crm
    include CrmHelper

    helper_method :crm_money?, :crm_capability
    # Redmine's menu_item registry is keyed by each concrete controller name;
    # return the shared CRM item so all namespaced controllers highlight CRM.
    def current_menu_item
      :crm
    end

    before_action :require_login
    before_action :enforce_crm_capability

    rescue_from ActiveRecord::StaleObjectError, :with => :render_conflict
    rescue_from ActiveRecord::RecordNotFound, :with => :render_not_found

    class << self
      def crm_model(klass = nil)
        @crm_model = klass if klass
        @crm_model
      end

      def model_class
        crm_model
      end
    end


    ROUTE_KEYS = %w[controller action id format commit utf8 authenticity_token].freeze
    MONEY_KEYS = %w[amount_cents currency weighted_cents weighted_amount open_cents].freeze

    protected

    def crm_user
      User.current
    end

    def crm_capability
      Crm::Access.capability(crm_user)
    end

    def crm_money?
      return @crm_money if defined?(@crm_money)

      @crm_money = Crm::Access.can_view_money?(crm_user)
    end

    def require_crm_read
      return true if %i[admin staff viewer contractor].include?(crm_capability)

      render_404
      false
    end

    def require_feed
      return true if Crm::Access.feed?(crm_user)

      render_403
      false
    end

    def deny_contractor_api
      return true unless Crm::Access.contractor?(crm_user) && api_request?

      render_403
      false
    end

    def enforce_crm_capability
      case crm_capability
      when :none
        render_404
        false
      when :feed
        return true if crm_feed_action_allowed?

        render_403
        false
      when :contractor
        if api_request?
          render_403
          false
        elsif controller_name == 'deals' && %w[index show board move].include?(action_name.to_s)
          render_404
          false
        else
          true
        end
      else
        true
      end
    end

    # Feed is intentionally denied by default.  The feed controller can override
    # this hook for its three narrow create actions; lookup is the only feed action
    # implemented by the resource controllers themselves.
    def crm_feed_action_allowed?
      false
    end

    def require_staff
      return true if Crm::Access.staff?(crm_user)

      render_403
      false
    end

    def crm_model_class
      self.class.model_class || "Crm#{controller_name.singularize.camelize}".constantize
    end


    def crm_record_key
      controller_name.singularize
    end

    def crm_record_alias(record = @record)
      @record = record
      instance_variable_set("@#{crm_record_key}", record)
      record
    end

    def include_values
      params[:include].to_s.split(',').map(&:strip).reject(&:blank?)
    end

    def include_requested?(name)
      !api_request? || include_values.include?(name.to_s)
    end

    def include_archived_requested?
      params[:include_archived].to_s == '1' || params[:include_archived].to_s.casecmp('true').zero? ||
        action_name.to_s == 'restore'
    end

    def crm_visible_scope(klass = crm_model_class, include_archived: include_archived_requested?)
      scope = begin
        klass.visible(crm_user, :include_archived => include_archived)
      rescue ArgumentError
        klass.visible(crm_user)
      end
      scope = scope.active if !include_archived && scope.respond_to?(:active)
      if include_archived && Crm::Access.reads_all?(crm_user) && scope.respond_to?(:unscope)
        scope = scope.unscope(:where => :archived_on)
      end
      scope
    end

    def find_record
      id = params[:id].presence
      return render_404 unless id

      crm_record = crm_visible_scope.find(id)
      crm_record_alias(crm_record)
    end

    def prepare_record_page(record = @record)
      crm_record_alias(record)
      @history_rows = if Crm::Access.reads_all?(crm_user) && include_requested?('changes')
                        crm_history_rows(record, crm_user)
                      else
                        []
                      end
      @timeline = crm_timeline(record)

      if include_requested?('attachments') && crm_files_visible?
        @attachments = record.attachments.to_a if record.respond_to?(:attachments)
      else
        @attachments = []
      end

      if include_requested?('links') && record.respond_to?(:links)
        @links = record.links.to_a
      else
        @links = []
      end

      if include_requested?('custom_fields') && record.respond_to?(:custom_field_values)
        @custom_fields = crm_visible_custom_values(record, crm_user)
      else
        @custom_fields = []
      end

      record
    end

    def crm_files_visible?
      Crm::Access.staff?(User.current) || Crm::Access.viewer?(User.current)
    end

    def retrieve_crm_query(query_class)
      # Query rows are global.  Contractors have no query metadata or session
      # state, so callers use the fixed default scope instead.
      @query = retrieve_query(query_class, !api_request?)
    rescue ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid
      render_404
      nil
    rescue Query::QueryError
      render_404
      nil
    end

    def setup_index(query_class, klass = crm_model_class, order: nil)
      if Crm::Access.reads_all?(User.current)
        return false unless retrieve_crm_query(query_class)

        @record_count = @query.result_count
        @offset, @limit = list_offset_and_limit
        @records = Array(@query.results(:offset => @offset, :limit => @limit))
      else
        @query = nil
        scope = crm_visible_scope(klass)
        scope = scope.order(order) if order
        @record_count = scope.count
        @offset, @limit = list_offset_and_limit
        @records = scope.offset(@offset).limit(@limit).to_a
      end
      true
    end

    def list_offset_and_limit
      if api_request?
        api_offset_and_limit
      else
        limit = per_page_option
        page = params[:page].to_i
        page = 1 if page < 1
        [(page - 1) * limit, limit]
      end
    end

    def record_params(model_class = crm_model_class)
      names = [model_class.name.underscore, crm_record_key].uniq
      candidate = names.lazy.map {|name| params[name] || params[name.to_sym] }.find(&:present?)
      if candidate.nil? && request.respond_to?(:request_parameters)
        request_values = request.request_parameters
        candidate = names.lazy.map {|name| request_values[name] || request_values[name.to_sym] }.find(&:present?)
      end

      values = if candidate
                  candidate
                elsif request.respond_to?(:request_parameters)
                  request.request_parameters
                else
                  params
                end
      values = values.to_unsafe_h if values.respond_to?(:to_unsafe_h)
      values = values.to_h if values.respond_to?(:to_h) && !values.is_a?(Hash)
      values = values.stringify_keys
      values = values.except(*ROUTE_KEYS)

      if values.key?('custom_fields') && !values.key?('custom_field_values')
        values['custom_field_values'] = values.delete('custom_fields')
      end
      values
    end

    alias resource_attributes record_params

    def precheck_safe_attributes!(record, attributes)
      values = attributes.respond_to?(:to_unsafe_h) ? attributes.to_unsafe_h : attributes.to_h
      values = values.stringify_keys
      values['custom_field_values'] = values.delete('custom_fields') if values.key?('custom_fields') && !values.key?('custom_field_values')
      values.delete('lock_version')
      allowed = if record.respond_to?(:safe_attribute_names)
                  record.safe_attribute_names(crm_user).map(&:to_s)
                elsif record.class.respond_to?(:safe_attribute_names)
                  record.class.safe_attribute_names(crm_user).map(&:to_s)
                else
                  values.keys
                end
      forbidden = values.keys.reject {|key| allowed.include?(key.to_s)}
      return true if forbidden.empty?

      render :json => {:errors => {:forbidden_attributes => forbidden.sort}}, :status => :unprocessable_entity
      false
    end

    def render_existing(record)
      crm_record_alias(record)
      if api_request?
        render :action => 'show', :status => :ok
      else
        render :json => {:id => record.id, :lock_version => record.try(:lock_version), :record => crm_record_payload(record)}, :status => :ok
      end
    end

    def with_lock_version(record, incoming_lock = nil)
      incoming_lock ||= record_params(record.class)['lock_version'] || params[:lock_version]
      if record.respond_to?(:lock_version) && (incoming_lock.blank? || record.lock_version.to_i != incoming_lock.to_i)
        return render_conflict
      end
      yield
    rescue ActiveRecord::StaleObjectError
      render_conflict
    end


    def existing_external_identity(attributes, klass = crm_model_class)
      values = attributes.stringify_keys
      scope = klass.unscoped
      if values['external_ref'].present? && klass.column_names.include?('external_ref')
        scope.find_by(:external_ref => values['external_ref'])
      elsif values['external_source'].present? && values['external_id'].present? &&
            klass.column_names.include?('external_source') && klass.column_names.include?('external_id')
        scope.find_by(:external_source => values['external_source'], :external_id => values['external_id'])
      end
    end

    # Returns [clean_attributes, nil] or [nil, error_hash].  lock_version is a
    # concurrency precondition rather than a safe attribute and is removed before
    # assigning through Redmine::SafeAttributes.
    def prepared_record_attributes(record, attributes, create: false)
      values = attributes.respond_to?(:to_unsafe_h) ? attributes.to_unsafe_h : attributes.to_h
      values = values.stringify_keys
      if values.key?('custom_fields') && !values.key?('custom_field_values')
        values['custom_field_values'] = values.delete('custom_fields')
      end

      incoming_lock = values.delete('lock_version')
      if !create && record.respond_to?(:lock_version)
        return [nil, {:error => 'conflict'}] if incoming_lock.blank?
        return [nil, {:error => 'conflict'}] if record.lock_version.to_i != incoming_lock.to_i
      end

      allowed = if record.respond_to?(:safe_attribute_names)
                  record.safe_attribute_names(User.current).map(&:to_s)
                elsif record.class.respond_to?(:safe_attribute_names)
                  record.class.safe_attribute_names(User.current).map(&:to_s)
                else
                  values.keys
                end
      forbidden = values.keys.reject {|key| allowed.include?(key.to_s)}
      return [nil, {:error => 'forbidden_attributes', :forbidden_keys => forbidden.sort}] if forbidden.any?

      [values, nil]
    end

    def assign_record_attributes(record, attributes, create: false)
      values, error = prepared_record_attributes(record, attributes, :create => create)
      if error
        if error[:error] == 'conflict'
          render_conflict
        else
          render_json_error(error, :unprocessable_entity)
        end
        return false
      end

      if record.respond_to?(:safe_attributes=)
        record.safe_attributes = values
      else
        values.each do |name, value|
          writer = "#{name}="
          record.public_send(writer, value) if record.respond_to?(writer)
        end
      end
      true
    end

    def render_json_error(payload, status = nil)
      if status.nil? && payload.is_a?(Hash) && payload.key?(:status)
        status = payload.delete(:status)
      end
      render :json => payload, :status => (status || :unprocessable_entity)
    end

    def render_record_errors(record, status: :unprocessable_entity)
      if api_request?
        render_validation_errors(record)
      else
        render_json_error(:error => 'validation', :messages => record.errors.full_messages, :errors => record.errors.to_hash, :status => status)
      end
    end

    def render_mutation_success(record, status: :ok)
      crm_record_alias(record)
      if api_request?
        render :action => 'show', :status => status
      else
        render :json => {:id => record.id, :lock_version => record.try(:lock_version), :record => crm_record_payload(record)}, :status => status
      end
    end

    def crm_record_payload(record)
      attributes = record.respond_to?(:attributes) ? record.attributes.deep_dup : {}
      unless crm_money?
        MONEY_KEYS.each {|key| attributes.delete(key)}
      end

      if attributes.key?('owner_id')
        attributes['owner'] = crm_owner_name(attributes.delete('owner_id'))
      end
      if attributes.key?('author_id')
        attributes['author'] = crm_owner_name(attributes.delete('author_id'))
      end
      attributes
    end

    def render_conflict(_exception = nil)
      render :json => {:error => 'conflict'}, :status => :conflict
    end

    def render_not_found(_exception = nil)
      render_404
    end

    def crm_timeline(record)
      activities = if record.respond_to?(:activities)
                     association = record.activities
                     association = association.visible(User.current) if association.respond_to?(:visible)
                     association.to_a
                   else
                     []
                   end
      rows = activities.map do |activity|
        {:kind => :activity, :at => (activity.occurred_at || activity.created_on), :item => activity}
      end

      if Crm::Access.reads_all?(crm_user) && defined?(CrmChange)
        changes = CrmChange.where(:record_type => record.class.name, :record_id => record.id).to_a
        redacted_rows = crm_history_rows(record, crm_user).index_by {|row| row[:id]}
        changes.each do |change|
          row = redacted_rows[change.id]
          next unless row

          item = change.dup
          item.old_value = row[:old_value] if item.respond_to?(:old_value=)
          item.value = row[:value] if item.respond_to?(:value=)
          rows << {:kind => :change, :at => row[:at], :item => item}
        end
      end
      rows.sort_by {|row| [row[:at] || Time.at(0), row[:item].try(:id).to_i] }.reverse
    end

    def bulk_items
      source = params[:records] || params[:items]
      source = source.to_unsafe_h if source.respond_to?(:to_unsafe_h)
      if source.respond_to?(:to_h) && !source.is_a?(Hash) && !source.is_a?(Array)
        source = source.to_h
      end

      if source.is_a?(Hash)
        source.map {|id, values| [id, values] }
      else
        ids = params[:ids] || source || []
        ids = ids.to_unsafe_h.keys if ids.respond_to?(:to_unsafe_h)
        Array(ids).map {|id| [id, {}] }
      end
    end

    def bulk_mutate_records(klass = crm_model_class)
      visible = crm_visible_scope(klass, :include_archived => true)
      common = params[:attributes] || params[:values] || {}
      results = []

      bulk_items.each do |id, raw_values|
        values = raw_values.presence || common
        values = values.to_unsafe_h if values.respond_to?(:to_unsafe_h)
        values = values.stringify_keys
        record = visible.find_by(:id => id)
        unless record
          results << {:id => id.to_i, :error => 'not_found'}
          next
        end

        action = values.delete('action') || params[:bulk_action].to_s
        begin
          if %w[archive restore].include?(action) && record.respond_to?(:lock_version) &&
              (values['lock_version'].blank? || record.lock_version.to_i != values['lock_version'].to_i)
            results << {:id => record.id, :error => 'conflict'}
            next
          end
          if action == 'archive'
            record.archive!(User.current)
          elsif action == 'restore'
            record.restore!(User.current)
          else
            prepared, error = prepared_record_attributes(record, values)
            if error
              results << error.merge(:id => record.id)
              next
            end
            record.safe_attributes = prepared
            record.save!
          end
          results << {:id => record.id, :ok => true, :lock_version => record.try(:lock_version)}
        rescue ActiveRecord::StaleObjectError
          results << {:id => record.id, :error => 'conflict'}
        rescue ActiveRecord::RecordInvalid => exception
          results << {:id => record.id, :error => 'validation', :messages => exception.record.errors.full_messages}
        end
      end

      render :json => {:results => results}, :status => :ok
    end
  end
end
