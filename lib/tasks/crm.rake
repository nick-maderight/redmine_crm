# frozen_string_literal: true

namespace :redmine do
  namespace :crm do
    desc 'Seed CRM groups, contractor role, pipeline stages and custom fields'
    task :setup => :environment do
      require File.expand_path('../redmine_crm/setup', __dir__)
      RedmineCrm::Setup.run!
      puts 'CRM setup complete (idempotent)'
    end

    desc 'Import the explicit-column Twenty CSV extraction (MODE=diff for a report-only run)'
    task :import_twenty => :environment do
      require File.expand_path('../redmine_crm/twenty_import', __dir__)
      directory = ENV['DIR'].presence || ENV['FILE'].presence
      raise ArgumentError, 'DIR=/path/to/twenty-csvs is required' if directory.to_s.empty?

      RedmineCrm::TwentyImport.call(
        :dir => directory,
        :mode => ENV['MODE'],
        :pocketbase_map => ENV['POCKETBASE_MAP']
      )
    end

    desc 'Export CRM rows and metadata as versioned JSON files (MONEY=redact to hide money)'
    task :export => :environment do
      require File.expand_path('../redmine_crm/export', __dir__)
      directory = ENV['DIR'].to_s
      raise ArgumentError, 'DIR=/path/to/export is required' if directory.empty?

      redact = if ENV.key?('MONEY')
                  ENV['MONEY'].to_s.downcase == 'redact'
                elsif ENV.key?('REDACT_MONEY')
                  %w[1 true yes redact].include?(ENV['REDACT_MONEY'].to_s.downcase)
                end
      files = RedmineCrm::Export.call(:dir => directory, :redact_money => redact)
      puts "CRM export wrote #{files.length} JSON files to #{File.expand_path(directory)}"
    end
  end
end
