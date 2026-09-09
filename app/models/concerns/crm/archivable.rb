# frozen_string_literal: true

module Crm
  module Archivable
    extend ActiveSupport::Concern

    included do
      scope :active, -> { where(:archived_on => nil) }
      scope :archived, -> { where.not(:archived_on => nil) }
    end

    # Redmine's search results page renders each hit through the acts_as_event interface.
    def event_type
      self.class.name.underscore.tr('_', '-')
    end

    def event_title
      title = respond_to?(:name) ? name.to_s : (respond_to?(:subject) ? subject.to_s : '')
      title.presence || "#{self.class.model_name.human} ##{id}"
    end

    def event_description
      text = respond_to?(:description) ? description : (respond_to?(:body) ? body : nil)
      text.to_s.truncate(255)
    end

    def event_datetime
      (respond_to?(:occurred_at) && occurred_at) || (respond_to?(:updated_on) && updated_on) || created_on
    end

    def event_author
      author_id = respond_to?(:author_id) ? self[:author_id] : (respond_to?(:owner_id) ? self[:owner_id] : nil)
      author_id && User.find_by(:id => author_id)
    end

    def event_url
      {:controller => "crm/#{self.class.name.sub(/\ACrm/, '').underscore.pluralize}", :action => 'show', :id => id, :only_path => true}
    end

    # CRM records are global: no project badge in search results.
    def project
      nil
    end

    class_methods do
      # API callers get active records unless they explicitly request archived rows.
      def for_api(user=User.current, include_archived: false)
        visible(user, :include_archived => include_archived)
      end

      # Search contract used by Redmine::Search. CRM records are global and do not
      # consult the projects argument or Redmine's project permission condition.
      def search_result_ranks_and_ids(tokens, user=User.current, _projects=nil, options={})
        return [] if options[:attachments] == 'only'

        tokens = Array(tokens).map(&:to_s).map(&:strip).reject(&:blank?)
        return [] if tokens.empty?

        columns = Array(options[:columns] || crm_search_columns).map(&:to_s)
        columns = columns.first(1) if options[:titles_only]
        return [] if columns.empty?

        scope = visible(user)
        base_ids = crm_search_ids(scope, columns, tokens, options)
        custom_ids = crm_search_custom_value_ids(scope, tokens, user, options)
        ids = (base_ids + custom_ids).uniq
        return [] if ids.empty?

        ranked = scope.where(:id => ids).
          reorder(:updated_on => :desc, :id => :desc).
          limit(options[:limit]).
          pluck(:updated_on, :id)
        ranked.map {|timestamp, id| [timestamp.to_i, id]}
      end

      def search_results_from_ids(ids)
        visible(User.current).where(:id => Array(ids)).to_a
      end

      def search_results(*args)
        search_results_from_ids(search_result_ranks_and_ids(*args).map(&:last))
      end

      def crm_search_columns
        []
      end

      private

      def crm_search_ids(scope, columns, tokens, options)
        quoted_table = connection.quote_table_name(table_name)
        field_sql = columns.map do |column|
          quoted_column = connection.quote_column_name(column)
          "#{quoted_table}.#{quoted_column} ILIKE ?"
        end
        clauses = tokens.map do |token|
          "(#{field_sql.join(' OR ')})"
        end
        sql = clauses.join(options[:all_words] ? ' AND ' : ' OR ')
        values = tokens.flat_map { |token| field_sql.map { |_field| "%#{sanitize_sql_like(token)}%" } }
        scope.where([sql, *values]).distinct.pluck(:id)
      end

      def crm_search_custom_value_ids(scope, tokens, user, options)
        field_class = "#{name}CustomField".safe_constantize
        return [] unless field_class && respond_to?(:reflect_on_association) && reflect_on_association(:custom_values)

        field_ids = field_class.visible(user).pluck(:id)
        return [] if field_ids.empty?

        clauses = tokens.map { |_token| 'custom_values.value ILIKE ?' }
        sql = clauses.join(options[:all_words] ? ' AND ' : ' OR ')
        values = tokens.map { |token| "%#{sanitize_sql_like(token)}%" }
        scope.joins(:custom_values).
          where(:custom_values => {:custom_field_id => field_ids}).
          where([sql, *values]).distinct.pluck(:id)
      end

      def sanitize_sql_like(value)
        ActiveRecord::Base.sanitize_sql_like(value)
      end
    end

    def archived?
      archived_on.present?
    end

    def merged?
      respond_to?(:merged_into_id) && merged_into_id.present?
    end

    def visible?(user=User.current)
      return false unless persisted?
      self.class.visible(user).where(:id => id).exists?
    end

    def attachments_visible?(user=User.current)
      Crm::Access.reads_all?(user) && visible?(user)
    end

    def attachments_editable?(user=User.current)
      Crm::Access.can_write?(user) && visible?(user)
    end

    def attachments_deletable?(user=User.current)
      Crm::Access.can_write?(user) && visible?(user)
    end

    def archive!(user=User.current)
      unless Crm::Access.can_archive?(user)
        errors.add(:base, :forbidden)
        raise ActiveRecord::RecordInvalid.new(self)
      end
      return self if archived?

      previous_actor = instance_variable_get(:@crm_audit_user)
      self.archived_on = Time.current
      instance_variable_set(:@crm_audit_user, user)
      save!
      self
    ensure
      instance_variable_set(:@crm_audit_user, previous_actor)
    end

    def restore!(user=User.current)
      unless Crm::Access.can_archive?(user)
        errors.add(:base, :forbidden)
        raise ActiveRecord::RecordInvalid.new(self)
      end
      return self unless archived?
      if merged?
        errors.add(:base, :merged_parent)
        raise ActiveRecord::RecordInvalid.new(self)
      end

      old_archived_on = archived_on
      previous_actor = instance_variable_get(:@crm_audit_user)
      self.archived_on = nil
      instance_variable_set(:@crm_audit_user, user)
      save!
      self
    rescue ActiveRecord::RecordNotUnique
      self.archived_on = old_archived_on
      errors.add(:base, :taken)
      raise ActiveRecord::RecordInvalid.new(self)
    rescue ActiveRecord::RecordInvalid
      self.archived_on = old_archived_on
      raise
    ensure
      instance_variable_set(:@crm_audit_user, previous_actor)
    end

    # PostgreSQL's partial uniqueness indexes are the final race guard. Convert
    # their exception into the same validation contract used by preflight checks.
    def save(*args, **options)
      super
    rescue ActiveRecord::RecordNotUnique
      errors.add(:base, :taken)
      false
    end

    def save!(*args, **options)
      super
    rescue ActiveRecord::RecordNotUnique
      errors.add(:base, :taken)
      raise ActiveRecord::RecordInvalid.new(self)
    end
  end
end
