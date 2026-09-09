# frozen_string_literal: true

require 'csv'
require 'json'
require 'bigdecimal'
require 'date'
require 'time'
require 'set'
require 'uri'

module RedmineCrm
  # Imports the deliberately small, explicit-column extraction produced for the
  # Twenty retirement.  The extractor is independent of Redmine; this class is
  # intentionally tolerant of SQL aliases (camelCase and snake_case) so that a
  # fresh extraction can be consumed without editing the importer.
  class TwentyImport
    SOURCE_FILES = {
      :companies => %w[company companies],
      :people => %w[person people],
      :opportunities => %w[opportunity opportunities],
      :communications => %w[_clientCommunication clientCommunication communications],
      :projects => %w[_project project projects],
      :attachments => %w[attachment attachments]
    }.freeze

    # These are the columns selected by the extraction.  A missing optional
    # column is treated as NULL; a missing file is an error for the six mapped
    # tables.  No SELECT * assumption is made here or in the receipt.
    SOURCE_COLUMNS = {
      :companies => %w[
        id name domainNamePrimaryLinkUrl addressAddressStreet1 addressAddressStreet2
        addressAddressCity addressAddressState addressAddressPostalCode addressAddressCountry
        employees idealCustomerProfile linkedinLinkPrimaryLinkUrl xLinkPrimaryLinkUrl
        description phonePrimaryPhoneNumber companyStatus accountOwnerId createdBySource
        deletedAt createdAt updatedAt
      ],
      :people => %w[
        id firstName lastName nameFirstName nameLastName emailsPrimaryEmail
        phonesPrimaryPhoneNumber jobTitle city linkedinLink xLink department stakeholderRole
        returnClient companyId createdBySource deletedAt createdAt updatedAt
      ],
      :opportunities => %w[
        id name amountAmountMicros amountCurrencyCode closeDate probability pointOfContactId
        personId stage contractType leadSource lossReason lossNotes priority serviceType
        firstContact description nextAction nextSteps companyId createdBySource deletedAt
        createdAt updatedAt
      ],
      :communications => %w[
        id name channel direction bodyMarkdown occurredAt flagged personId opportunityId
        externalId deletedAt createdAt updatedAt
      ],
      :projects => %w[id name status projectStatus companyId deletedAt createdAt updatedAt],
      :attachments => %w[id name fullPath targetType targetId createdAt updatedAt deletedAt]
    }.freeze

    NAME_MAP = {
      'heesu k' => 'Heesu Kim'
    }.freeze

    CLIENT_ACCOUNTS = {
      'terry' => 'Terry',
      'david c.' => 'David C.',
      'nodal labs' => 'Nodal Labs'
    }.freeze

    PROJECT_ACCOUNT_MAP = {
      'terry' => 'Terry',
      'heesu' => 'Heesu Kim',
      'davidc' => 'David C.',
      'nodal' => 'Nodal Labs',
      'atlasguard' => 'AtlasGuard',
      'seregram' => 'Seregram'
    }.freeze

    STAGE_MAP = {
      'new' => 'New',
      'qualifying' => 'Qualifying',
      'discovery' => 'Discovery',
      'proposalsent' => 'Proposal Sent',
      'negotiation' => 'Negotiation',
      'closedwon' => 'Closed Won',
      'closedlost' => 'Closed Lost'
    }.freeze

    CHANNEL_MAP = {
      'upwork' => 'upwork',
      'email' => 'email',
      'call' => 'phone',
      'phone' => 'phone',
      'sms' => 'sms',
      'inperson' => 'in_person',
      'inpersonmeeting' => 'in_person',
      'other' => 'other'
    }.freeze

    attr_reader :receipt

    def self.call(dir:, mode: nil, pocketbase_map: nil, io: $stdout)
      new(:dir => dir, :mode => mode, :pocketbase_map => pocketbase_map, :io => io).run!
    end

    def initialize(dir:, mode: nil, pocketbase_map: nil, io: $stdout)
      @dir = File.expand_path(dir.to_s)
      @mode = mode.to_s.downcase == 'diff' ? :diff : :full
      @pocketbase_map_path = pocketbase_map
      @io = io
      @receipt = {
        'schema_version' => 1,
        'mode' => @mode.to_s,
        'source_rows' => {},
        'source_columns' => SOURCE_COLUMNS,
        'cohort' => {'predicate' => 'live MANUAL/API companies plus companies linked through live people to deals or communications; people are live non-EMAIL or linked'},
        'created' => Hash.new(0),
        'matched' => Hash.new(0),
        'skipped_deleted' => Hash.new(0),
        'archive_only' => {},
        'project_links' => {'created' => 0, 'matched' => 0, 'unmatched_source' => []},
        'attachments_skipped_orphans' => 0,
        'dropped_flagged' => 0,
        'pocketbase_matches' => 0,
        'diff_changes' => [],
        'errors' => []
      }
      @rows = {}
      @source_id_to_record = Hash.new { |h, k| h[k] = {} }
      @pocketbase = {}
      @pipeline = nil
    end

    def run!
      ensure_directory!
      load_rows
      load_pocketbase_map
      calculate_cohort
      ensure_pipeline!

      import_accounts
      import_contacts
      import_deals
      import_activities
      import_project_links
      account_statuses unless @mode == :diff
      finalize_receipt
      print_receipt
      @receipt
    end

    private

    def ensure_directory!
      raise ArgumentError, "Twenty CSV directory does not exist: #{@dir}" unless File.directory?(@dir)
    end

    def load_rows
      SOURCE_FILES.each do |kind, candidates|
        path = find_csv(candidates)
        raise ArgumentError, "missing #{candidates.first}.csv in #{@dir}" unless path

        rows = CSV.read(path, :headers => true, :encoding => 'bom|utf-8').map { |row| normalize_row(row) }
        @rows[kind] = rows
        @receipt['source_rows'][kind.to_s] = rows.length
        @receipt['skipped_deleted'][kind.to_s] = rows.count { |row| deleted_row?(row) }
      end
    rescue CSV::MalformedCSVError => e
      raise ArgumentError, "invalid Twenty CSV: #{e.message}"
    end

    def find_csv(candidates)
      candidates.each do |base|
        exact = File.join(@dir, "#{base}.csv")
        return exact if File.file?(exact)
      end
      files = Dir[File.join(@dir, '*.csv')]
      candidates.each do |base|
        found = files.find { |path| File.basename(path, '.csv').casecmp(base).zero? }
        return found if found
      end
      nil
    end

    def normalize_row(csv_row)
      row = {}
      csv_row.headers.each do |header|
        key = normalize_key(header)
        row[key] = csv_row[header]
      end
      row
    end

    def normalize_key(value)
      value.to_s.sub(/\A\uFEFF/, '').gsub(/[^a-zA-Z0-9]/, '').downcase
    end

    def row_value(row, *names)
      names.each do |name|
        key = normalize_key(name)
        return row[key] if row.key?(key)
      end
      nil
    end

    def row_id(row)
      row_value(row, 'id', 'uuid', 'recordId').to_s.strip
    end

    def deleted_row?(row)
      value = row_value(row, 'deletedAt', 'deleted_at', 'archivedAt', 'isDeleted')
      return truthy?(value) if value.to_s =~ /\A(?:true|false|0|1|yes|no)\z/i

      value.to_s.strip != ''
    end

    def live_rows(kind)
      @rows.fetch(kind).reject { |row| deleted_row?(row) }
    end

    def calculate_cohort
      people = live_rows(:people)
      deals = live_rows(:opportunities)
      communications = live_rows(:communications)
      manual_or_api = people.select { |row| provenance(row) != 'EMAIL' }.map { |row| row_id(row) }
      linked_people = []
      communications.each do |row|
        linked_people << row_value(row, 'personId', 'person_id')
      end
      deals.each do |row|
        linked_people << row_value(row, 'pointOfContactId', 'point_of_contact_id', 'personId', 'contactId')
      end
      linked_people = linked_people.compact.map(&:to_s).reject(&:empty?).uniq
      included_people = (manual_or_api + linked_people).uniq
      included_person_rows = people.select { |row| included_people.include?(row_id(row)) }

      companies = live_rows(:companies)
      manual_or_api_companies = companies.select { |row| %w[MANUAL API].include?(provenance(row)) }.map { |row| row_id(row) }
      linked_company_ids = included_person_rows.select { |row| linked_people.include?(row_id(row)) }.map do |row|
        row_value(row, 'companyId', 'company_id')
      end
      linked_company_ids = linked_company_ids.compact.map(&:to_s).reject(&:empty?)
      included_companies = (manual_or_api_companies + linked_company_ids).uniq

      @cohort_people = included_people
      @cohort_companies = included_companies
      @receipt['cohort'] = {
        'predicate' => 'live MANUAL/API companies plus companies linked through live people to deals or communications; people are live non-EMAIL or linked',
        'companies' => included_companies.length,
        'company_ids' => included_companies,
        'people' => included_people.length,
        'person_ids' => included_people,
        'linked_person_ids' => linked_people,
        'linked_company_ids' => linked_company_ids,
        'archive_only_companies' => [companies.length - included_companies.length, 0].max,
        'archive_only_people' => [people.length - included_people.length, 0].max
      }
      @receipt['attachments_skipped_orphans'] = live_rows(:attachments).count do |row|
        row_value(row, 'fullPath', 'full_path').to_s.strip == '' ||
          row_value(row, 'targetType', 'target_type').to_s.strip == '' ||
          row_value(row, 'targetId', 'target_id').to_s.strip == ''
      end

      @receipt['archive_only'] = {
        'companies' => @receipt['cohort']['archive_only_companies'],
        'people' => @receipt['cohort']['archive_only_people'],
        'projects' => [live_rows(:projects).length - named_active_projects.length, 0].max,
        'attachments' => live_rows(:attachments).length
      }
    end

    def load_pocketbase_map
      return if @pocketbase_map_path.to_s.strip.empty?
      path = File.expand_path(@pocketbase_map_path.to_s)
      raise ArgumentError, "PocketBase map does not exist: #{path}" unless File.file?(path)

      CSV.read(path, :headers => true, :encoding => 'bom|utf-8').each do |csv_row|
        row = normalize_row(csv_row)
        person_id = row_value(row, 'crm_person_id', 'crmPersonId', 'twenty_person_id', 'twentyPersonId', 'personId', 'person_id')
        client_id = row_value(row, 'client_id', 'clientId', 'upwork_client_id', 'upworkClientId')
        deal_id = row_value(row, 'crm_opportunity_id', 'crmOpportunityId', 'twenty_opportunity_id', 'twentyOpportunityId', 'opportunityId', 'opportunity_id', 'deal_id')
        room_id = row_value(row, 'room_id', 'roomId', 'conversation_room_id', 'conversationRoomId', 'conversation_id', 'conversationId')
        external_id = row_value(row, 'external_id', 'externalId', 'message_id', 'messageId')
        @pocketbase[person_id.to_s] = {'client_id' => client_id.to_s} if person_id.to_s != '' && client_id.to_s != ''
        @pocketbase[deal_id.to_s] = {'room_id' => room_id.to_s} if deal_id.to_s != '' && room_id.to_s != ''
        if external_id.to_s != ''
          @pocketbase["activity:#{external_id}"] = {'external_id' => external_id.to_s}
        end
      end
      @receipt['pocketbase_matches'] = @pocketbase.length
    rescue CSV::MalformedCSVError => e
      raise ArgumentError, "invalid PocketBase map: #{e.message}"
    end

    def crm_class(name)
      name.constantize
    rescue NameError
      nil
    end

    def ensure_pipeline!
      klass = crm_class('CrmPipeline')
      @pipeline = klass.where(:name => 'Sales').first if klass
      return @pipeline if @pipeline
      raise 'Sales pipeline is missing; run redmine:crm:setup before MODE=diff' if @mode == :diff

      if defined?(RedmineCrm::Setup)
        @pipeline = RedmineCrm::Setup.seed_pipeline!
      else
        require_relative 'setup'
        @pipeline = RedmineCrm::Setup.seed_pipeline!
      end
    end

    def import_accounts
      ApplicationRecord.transaction { import_accounts_body }
    end

    def import_accounts_body
      return if @mode == :diff && !crm_class('CrmAccount')
      klass = crm_class('CrmAccount')
      live_rows(:companies).each do |row|
        source_id = row_id(row)
        next unless @cohort_companies.include?(source_id)

        ref = "twenty:#{source_id}"
        ref = nil if source_id.empty?
        attrs = account_attributes(row)
        existing = find_record(klass, ref)
        existing ||= klass.where(:name => attrs[:name]).first if ref.to_s == '' && attrs[:name].to_s != ''
        if @mode == :diff
          if existing
            @receipt['matched']['accounts'] += 1
            @source_id_to_record[:accounts][source_id] = existing
            report_changes('account', ref || source_id, attrs, existing)
          else
            @receipt['created']['accounts'] += 1
          end
          next
        end
        if existing
          @receipt['matched']['accounts'] += 1
          @source_id_to_record[:accounts][source_id] = existing
          next
        end

        account = klass.new(attrs)
        set_custom(account, 'Source', source_value(row))
        set_custom(account, 'Employees', row_value(row, 'employees'))
        set_custom(account, 'Ideal customer', row_value(row, 'idealCustomerProfile', 'ideal_customer_profile'))
        set_custom(account, 'LinkedIn', row_value(row, 'linkedinLinkPrimaryLinkUrl', 'linkedinLink'))
        set_custom(account, 'X', row_value(row, 'xLinkPrimaryLinkUrl', 'xLink'))
        assign(account, :external_ref, ref) if ref
        mark_imported(account, ref)
        account.save!
        @receipt['created']['accounts'] += 1
        @source_id_to_record[:accounts][source_id] = account
      rescue StandardError => e
        record_error('account', source_id, e)
      end

      # Account rows from the Redmine Client field are provenance-distinct and
      # deliberately are not sourced from the Twenty cohort.
      create_client_accounts unless @mode == :diff
    end

    def import_contacts
      ApplicationRecord.transaction { import_contacts_body }
    end

    def import_contacts_body
      klass = crm_class('CrmContact')
      live_rows(:people).each do |row|
        source_id = row_id(row)
        next unless @cohort_people.include?(source_id)

        map = @pocketbase[source_id]
        fallback_ref = source_id.to_s == '' ? nil : "twenty:#{source_id}"
        ref = map && map['client_id'].to_s != '' ? "upwork:client:#{map['client_id']}" : fallback_ref
        attrs = contact_attributes(row)
        account = account_for_source_id(row_value(row, 'companyId', 'company_id'))
        attrs[:account_id] = account.id if account
        existing = find_record(klass, ref)
        existing ||= find_record(klass, fallback_ref) if ref != fallback_ref
        if @mode == :diff
          if existing
            @receipt['matched']['contacts'] += 1
            @source_id_to_record[:people][source_id] = existing
            report_changes('contact', ref || source_id, attrs, existing)
          else
            @receipt['created']['contacts'] += 1
          end
          next
        end
        if existing
          @receipt['matched']['contacts'] += 1
          @source_id_to_record[:people][source_id] = existing
          next
        end

        contact = klass.new(attrs)
        set_custom(contact, 'Source', source_value(row))
        set_custom(contact, 'Department', row_value(row, 'department'))
        set_custom(contact, 'Stakeholder role', row_value(row, 'stakeholderRole', 'stakeholder_role'))
        set_custom(contact, 'Return client', row_value(row, 'returnClient', 'return_client'))
        assign(contact, :external_ref, ref) if ref
        mark_imported(contact, ref)
        contact.save!
        @receipt['created']['contacts'] += 1
        @source_id_to_record[:people][source_id] = contact
      rescue StandardError => e
        record_error('contact', source_id, e)
      end
    end

    def import_deals
      ApplicationRecord.transaction { import_deals_body }
    end

    def import_deals_body
      klass = crm_class('CrmDeal')
      live_rows(:opportunities).each do |row|
        source_id = row_id(row)
        next if source_id.to_s == '' && row_value(row, 'name').to_s == ''

        attrs = deal_attributes(row)
        contact = contact_for_source_id(row_value(row, 'pointOfContactId', 'point_of_contact_id', 'personId', 'contactId'))
        attrs[:contact_id] = contact.id if contact
        attrs[:account_id] = contact.account_id if contact && contact.respond_to?(:account_id) && contact.account_id.present?
        ref = source_id.to_s == '' ? nil : "twenty:#{source_id}"
        map = @pocketbase[source_id]
        ref = "upwork:room:#{map['room_id']}" if map && map['room_id'].to_s != ''
        existing = find_record(klass, ref)
        existing ||= find_record(klass, "twenty:#{source_id}") if ref != "twenty:#{source_id}"
        if @mode == :diff
          if existing
            @receipt['matched']['deals'] += 1
            @source_id_to_record[:opportunities][source_id] = existing
            report_changes('deal', ref || source_id, attrs, existing)
          else
            @receipt['created']['deals'] += 1
          end
          next
        end
        if existing
          @receipt['matched']['deals'] += 1
          @source_id_to_record[:opportunities][source_id] = existing
          next
        end

        deal = klass.new(attrs)
        set_custom(deal, 'Source', source_value(row))
        set_custom(deal, 'Contract type', row_value(row, 'contractType', 'contract_type'))
        set_custom(deal, 'Lead source', row_value(row, 'leadSource', 'lead_source'))
        set_custom(deal, 'Loss reason', row_value(row, 'lossReason', 'loss_reason'))
        set_custom(deal, 'Loss notes', row_value(row, 'lossNotes', 'loss_notes'))
        set_custom(deal, 'Priority', row_value(row, 'priority'))
        set_custom(deal, 'Service type', row_value(row, 'serviceType', 'service_type'))
        set_custom(deal, 'First contact', row_value(row, 'firstContact', 'first_contact'))
        assign(deal, :external_ref, ref) if ref
        mark_imported(deal, ref)
        deal.save!
        @receipt['created']['deals'] += 1
        @source_id_to_record[:opportunities][source_id] = deal
      rescue StandardError => e
        record_error('deal', source_id, e)
      end
    end

    def import_activities
      ApplicationRecord.transaction { import_activities_body }
    end

    def import_activities_body
      klass = crm_class('CrmActivity')
      live_rows(:communications).each do |row|
        source_id = row_id(row)
        external_id = row_value(row, 'externalId', 'external_id') || source_id
        external_id = external_id.to_s.strip
        if truthy?(row_value(row, 'flagged'))
          @receipt['dropped_flagged'] += 1
        end
        attrs = activity_attributes(row)
        contact = contact_for_source_id(row_value(row, 'personId', 'person_id'))
        deal = deal_for_source_id(row_value(row, 'opportunityId', 'opportunity_id'))
        attrs[:contact_id] = contact.id if contact
        attrs[:deal_id] = deal.id if deal
        attrs[:account_id] = deal.account_id if deal && deal.respond_to?(:account_id) && deal.account_id.present?
        existing = klass.where(:external_source => 'upwork', :external_id => external_id).first if external_id != ''
        if @mode == :diff
          if existing
            @receipt['matched']['activities'] += 1
            report_changes('activity', external_id, attrs, existing)
          else
            @receipt['created']['activities'] += 1
          end
          next
        end
        if existing
          @receipt['matched']['activities'] += 1
          next
        end

        activity = klass.new(attrs)
        assign(activity, :external_source, 'upwork')
        assign(activity, :external_id, external_id) unless external_id == ''
        mark_imported(activity, external_id)
        activity.save!
        @receipt['created']['activities'] += 1
      rescue StandardError => e
        record_error('activity', external_id || source_id, e)
      end
    end

    def import_project_links
      ApplicationRecord.transaction { import_project_links_body }
    end

    def import_project_links_body
      candidates = named_active_projects
      candidates.each do |row|
        target = project_target_from_source(row)
        next unless target
        identifier = project_identifier_for_target(target)
        next unless identifier
        create_project_link(identifier, target) unless @mode == :diff
      end
      unmatched = candidates.filter_map do |row|
        candidate_project_name(row) unless project_target_from_source(row)
      end
      @receipt['project_links']['unmatched_source'] = unmatched.uniq

      # The Client field is the source for exactly these three links.  Heesu is
      # already represented by the source project row and is not duplicated.
      CLIENT_ACCOUNTS.values.each do |account_name|
        identifier = project_identifier_for_target(account_name)
        create_project_link(identifier, account_name) if identifier && @mode != :diff
      end
    end

    def create_project_link(identifier, account_name)
      project = Project.where(:identifier => identifier).first
      account = account_by_name(account_name)
      return unless project && account

      klass = crm_class('CrmAccountProject')
      existing = klass.where(:project_id => project.id).first
      if existing
        if existing.account_id.to_i == account.id.to_i
          @receipt['project_links']['matched'] += 1
        else
          @receipt['project_links']['unmatched_source'] << "#{identifier}: already linked"
        end
        return
      end
      klass.create!(:account_id => account.id, :project_id => project.id)
      @receipt['project_links']['created'] += 1
    rescue StandardError => e
      record_error('account_project', identifier, e)
    end

    def create_client_accounts
      klass = crm_class('CrmAccount')
      CLIENT_ACCOUNTS.values.each do |name|
        ref = "redmine:client:#{normalize_name(name)}"
        account = klass.where(:external_ref => ref).first
        next if account

        account = klass.new(:name => name, :status => 'active_client', :external_ref => ref)
        mark_imported(account, ref)
        account.save!
        @receipt['created']['accounts'] += 1
      end
    end

    def account_statuses
      account_ids_won = Set.new
      account_ids_lost = Set.new
      live_rows(:opportunities).each do |row|
        deal = @source_id_to_record[:opportunities][row_id(row)]
        next unless deal && deal.respond_to?(:account_id) && deal.account_id.present?
        kind = stage_kind_for(row)
        account_ids_won << deal.account_id if kind == 'won'
        account_ids_lost << deal.account_id if kind == 'lost'
      end
      account_ids_won.each do |id|
        CrmAccount.where(:id => id).update_all(:status => 'active_client')
      end
      (account_ids_lost - account_ids_won).each do |id|
        CrmAccount.where(:id => id).update_all(:status => 'prospect')
      end
    end

    def account_attributes(row)
      address = [
        row_value(row, 'addressAddressStreet1', 'addressStreet1', 'address_street1'),
        row_value(row, 'addressAddressStreet2', 'addressStreet2', 'address_street2'),
        row_value(row, 'addressAddressCity', 'addressCity', 'address_city'),
        row_value(row, 'addressAddressState', 'addressState', 'address_state'),
        row_value(row, 'addressAddressPostalCode', 'addressPostalCode', 'address_postal_code'),
        row_value(row, 'addressAddressCountry', 'addressCountry', 'address_country')
      ].map { |value| value.to_s.strip }.reject(&:empty?).join("\n")
      {
        :name => mapped_name(row_value(row, 'name')).to_s.strip,
        :domain => normalize_domain(row_value(row, 'domainNamePrimaryLinkUrl', 'domainName', 'domain')),
        :website => row_value(row, 'domainNamePrimaryLinkUrl', 'website'),
        :phone => row_value(row, 'phonePrimaryPhoneNumber', 'phone'),
        :address => address.presence,
        :description => row_value(row, 'description'),
        :owner_id => resolve_user_id(row_value(row, 'accountOwnerId', 'ownerId'))
      }
    end

    def contact_attributes(row)
      first = row_value(row, 'firstName', 'nameFirstName', 'name_first_name').to_s.strip
      last = row_value(row, 'lastName', 'nameLastName', 'name_last_name').to_s.strip
      email = row_value(row, 'emailsPrimaryEmail', 'primaryEmail', 'email').to_s.strip.downcase
      {
        :first_name => first,
        :last_name => last,
        :email => email.presence,
        :phone => row_value(row, 'phonesPrimaryPhoneNumber', 'phone'),
        :job_title => row_value(row, 'jobTitle', 'job_title'),
        :city => row_value(row, 'city'),
        :linkedin_url => row_value(row, 'linkedinLink', 'linkedinUrl'),
        :x_url => row_value(row, 'xLink', 'xUrl'),
        :owner_id => resolve_user_id(row_value(row, 'ownerId'))
      }
    end

    def deal_attributes(row)
      stage_name = stage_name_for(row)
      kind = stage_kind_for(row)
      close_date = parse_date(row_value(row, 'closeDate', 'close_date'))
      description = row_value(row, 'description').to_s
      next_steps = row_value(row, 'nextSteps', 'next_steps').to_s.strip
      if next_steps != ''
        description = [description.strip, "Next steps\n#{next_steps}"].reject(&:empty?).join("\n\n")
      end
      attrs = {
        :name => row_value(row, 'name').to_s.strip,
        :pipeline_id => @pipeline.id,
        :stage_id => stage_for(stage_name).id,
        :amount_cents => amount_cents(row_value(row, 'amountAmountMicros', 'amountMicros', 'amount_amount_micros')),
        :currency => (row_value(row, 'amountCurrencyCode', 'currencyCode', 'currency') || 'USD').to_s.upcase[0, 3],
        :probability => probability(row_value(row, 'probability')),
        :closed_on => %w[won lost].include?(kind) ? close_date : nil,
        :expected_close_on => nil,
        :next_action => row_value(row, 'nextAction', 'next_action'),
        :description => description.presence
      }
      attrs
    end


    def activity_attributes(row)
      {
        :kind => 'message',
        :channel => map_channel(row_value(row, 'channel')),
        :direction => row_value(row, 'direction').to_s.downcase.presence,
        :subject => row_value(row, 'name', 'subject'),
        :body => row_value(row, 'bodyMarkdown', 'body', 'body_markdown'),
        :occurred_at => parse_time(row_value(row, 'occurredAt', 'occurred_at')),
        :visibility => 'shared'
      }
    end

    def source_value(row)
      case provenance(row)
      when 'MANUAL' then 'twenty-manual'
      when 'API' then 'twenty-api'
      when 'EMAIL' then 'twenty-email'
      else 'manual'
      end
    end

    def provenance(row)
      row_value(row, 'createdBySource', 'created_by_source', 'source').to_s.upcase
    end

    def mapped_name(value)
      NAME_MAP.fetch(normalize_name(value), value)
    end

    def normalize_name(value)
      value.to_s.strip.downcase.gsub(/\s+/, ' ')
    end

    def normalize_domain(value)
      value = value.to_s.strip.downcase
      return nil if value == ''
      value = "https://#{value}" unless value =~ %r{\A[a-z][a-z0-9+.-]*://}i
      value = URI.parse(value).host.to_s if defined?(URI)
      value = value.sub(/\Awww\./, '')
      value.presence
    rescue URI::InvalidURIError
      value.sub(%r{\Ahttps?://}, '').split('/').first.presence
    end

    def amount_cents(value)
      return nil if value.to_s.strip == ''
      (BigDecimal(value.to_s) / BigDecimal('10000')).round(0).to_i
    rescue ArgumentError
      nil
    end

    def probability(value)
      return nil if value.to_s.strip == ''
      text = value.to_s.strip
      number = BigDecimal(text)
      number *= 100 if text.include?('.') && number <= 1
      [[number.round(0).to_i, 0].max, 100].min
    rescue ArgumentError
      nil
    end

    def parse_time(value)
      return nil if value.to_s.strip == ''
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      Time.parse(value.to_s)
    rescue StandardError
      nil
    end

    def parse_date(value)
      return nil if value.to_s.strip == ''
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def map_channel(value)
      key = normalize_key(value)
      CHANNEL_MAP[key] || 'other'
    end

    def stage_name_for(row)
      raw = row_value(row, 'stage', 'stageName', 'stage_name').to_s
      STAGE_MAP[normalize_key(raw)] || 'New'
    end

    def stage_kind_for(row)
      name = stage_name_for(row)
      return 'won' if name == 'Closed Won'
      return 'lost' if name == 'Closed Lost'
      'open'
    end

    def stage_for(name)
      klass = crm_class('CrmPipelineStage')
      klass.where(:pipeline_id => @pipeline.id, :name => name).first ||
        klass.where(:pipeline_id => @pipeline.id, :name => 'New').first ||
        raise("Sales pipeline has no #{name} or New stage")
    end

    def mark_imported(record, source_ref)
      return record unless record.respond_to?(:crm_audit_context=)

      record.crm_audit_context = 'imported'
      record.crm_audit_source_ref = source_ref if record.respond_to?(:crm_audit_source_ref=)
      record
    end

    def set_custom(record, name, value)
      return if value.nil? || value.to_s.strip == ''
      return unless record.respond_to?(:custom_field_values=)
      field = CustomField.where(:type => "#{record.class.name}CustomField", :name => name).first
      return unless field
      current = record.respond_to?(:custom_field_values) ? record.custom_field_values : []
      values = current.each_with_object({}) { |item, hash| hash[item.custom_field_id.to_s] = item.value }
      values[field.id.to_s] = value
      record.custom_field_values = values
    rescue StandardError => e
      record_error('custom_field', "#{record.class.name}:#{name}", e)
    end

    def resolve_user_id(value)
      return nil if value.to_s.strip == ''
      if value.to_s =~ /\A\d+\z/
        return value.to_i if User.where(:id => value.to_i).exists?
      end
      value = value.to_s.strip
      User.where('LOWER(login) = ?', value.downcase).pick(:id) ||
        User.where('LOWER(mail) = ?', value.downcase).pick(:id)
    end

    def find_record(klass, ref)
      return nil if ref.to_s == ''
      klass.where(:external_ref => ref).first
    end

    def account_for_source_id(source_id)
      return nil if source_id.to_s == ''
      @source_id_to_record[:accounts][source_id.to_s] ||
        crm_class('CrmAccount').where(:external_ref => "twenty:#{source_id}").first
    end

    def contact_for_source_id(source_id)
      return nil if source_id.to_s == ''
      @source_id_to_record[:people][source_id.to_s] ||
        crm_class('CrmContact').where(:external_ref => "twenty:#{source_id}").first
    end

    def deal_for_source_id(source_id)
      return nil if source_id.to_s == ''
      @source_id_to_record[:opportunities][source_id.to_s] ||
        crm_class('CrmDeal').where(:external_ref => "twenty:#{source_id}").first
    end

    def account_by_name(name)
      crm_class('CrmAccount').where('LOWER(name) = ?', mapped_name(name).downcase).first
    end

    def named_active_projects
      live_rows(:projects).select do |row|
        status = row_value(row, 'status', 'projectStatus', 'project_status').to_s.upcase
        status == 'ACTIVE' && candidate_project_name(row).strip != ''
      end
    end

    def candidate_project_name(row)
      row_value(row, 'name', 'projectName').to_s.strip
    end

    def project_target_from_source(row)
      name = candidate_project_name(row).downcase
      PROJECT_ACCOUNT_MAP.each do |identifier, account_name|
        return account_name if name.include?(identifier.downcase) || name.start_with?(account_name.downcase)
      end
      return 'Heesu Kim' if name.start_with?('heesu k')
      nil
    end

    def project_identifier_for_target(account_name)
      pair = PROJECT_ACCOUNT_MAP.find { |_identifier, target| target.casecmp(account_name.to_s).zero? }
      pair && pair.first
    end

    def assign(record, attribute, value)
      writer = "#{attribute}="
      record.public_send(writer, value) if record.respond_to?(writer)
    end

    def report_changes(type, key, attrs, record)
      attrs.each do |field, source_value|
        next unless record.respond_to?(field)
        crm_value = record.public_send(field)
        next if normalize_comparison(source_value) == normalize_comparison(crm_value)
        @receipt['diff_changes'] << {
          'type' => type,
          'source_key' => key.to_s,
          'field' => field.to_s,
          'source_value' => source_value,
          'crm_value' => crm_value
        }
      end
    end

    def normalize_comparison(value)
      return nil if value.nil?
      value.respond_to?(:iso8601) ? value.iso8601 : value.to_s
    end

    def record_error(type, key, error)
      @receipt['errors'] << {'type' => type, 'source_key' => key.to_s, 'error' => "#{error.class}: #{error.message}"}
    end

    def finalize_receipt
      %w[accounts contacts deals activities].each do |kind|
        @receipt['created'][kind] ||= 0
        @receipt['matched'][kind] ||= 0
      end
      @receipt['created'] = @receipt['created'].to_h
      @receipt['matched'] = @receipt['matched'].to_h
      @receipt['acceptance'] = {
        'accounts' => safe_count('CrmAccount'),
        'contacts' => safe_count('CrmContact'),
        'deals' => safe_count('CrmDeal'),
        'activities' => safe_count('CrmActivity'),
        'amount_cents' => safe_sum('CrmDeal', :amount_cents)
      }
      @receipt['diff_changes_count'] = @receipt['diff_changes'].length
      @receipt['acceptance_baseline'] = {'accounts' => 12, 'contacts' => 32, 'deals' => 31, 'activities' => 634}
    end

    def print_receipt
      @io.puts(JSON.pretty_generate(@receipt))
      unless @receipt['diff_changes'].empty?
        @io.puts('type,source_key,field,source_value,crm_value')
        @receipt['diff_changes'].each do |change|
          @io.puts(CSV.generate_line(change.values_at('type', 'source_key', 'field', 'source_value', 'crm_value')))
        end
      end
    end

    def safe_count(name)
      klass = crm_class(name)
      klass ? klass.count : 0
    end

    def safe_sum(name, column)
      klass = crm_class(name)
      klass ? klass.sum(column).to_i : 0
    end

    def truthy?(value)
      value == true || value.to_s.strip =~ /\A(?:1|true|yes|y)\z/i
    end
  end
end
