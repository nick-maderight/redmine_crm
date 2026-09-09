# frozen_string_literal: true

# Two disjoint route sets (design: REST API → Route declaration rule):
#  * API routes require an explicit .json/.xml format and API-key identity.
#  * Browser routes are extensionless (format: false), use the Redmine session, take a JSON
#    body where they mutate, and are protected by Redmine's ordinary CSRF verification.
API_FORMAT = {:format => /json|xml/}.freeze

scope :module => 'crm', :as => 'crm' do
  # ---------------------------------------------------------------- API (.json / .xml)
  scope :constraints => API_FORMAT, :format => true do
    # Lookup is a named collection endpoint and must precede the generic
    # /:id route, otherwise Rails treats "lookup" as a contact id.
    get  '/crm/contacts/lookup',       :to => 'contacts#lookup'
    get  '/crm/deals/lookup',          :to => 'deals#lookup'

    %w(accounts contacts deals activities).each do |type|
      get    "/crm/#{type}",             :to => "#{type}#index",   :as => "api_#{type}"
      post   "/crm/#{type}",             :to => "#{type}#create"
      get    "/crm/#{type}/:id",         :to => "#{type}#show",    :as => "api_#{type.singularize}"
      match  "/crm/#{type}/:id",         :to => "#{type}#update",  :via => [:put, :patch]
      put    "/crm/#{type}/:id/archive", :to => "#{type}#archive"
      put    "/crm/#{type}/:id/restore", :to => "#{type}#restore"
    end
    put  '/crm/deals/:id/move',        :to => 'deals#move'
    post '/crm/accounts/:id/links',    :to => 'links#create',  :defaults => {:record_type => 'account'}
    post '/crm/contacts/:id/links',    :to => 'links#create',  :defaults => {:record_type => 'contact'}
    post '/crm/deals/:id/links',       :to => 'links#create',  :defaults => {:record_type => 'deal'}
    delete '/crm/links/:id',           :to => 'links#destroy'
    post '/crm/accounts/:id/projects', :to => 'account_projects#create'
    delete '/crm/accounts/:id/projects/:project_id', :to => 'account_projects#destroy'
    post '/crm/feed/contacts',         :to => 'feed#create_contact'
    post '/crm/feed/deals',            :to => 'feed#create_deal'
    post '/crm/feed/activities',       :to => 'feed#create_activity'
    put  '/crm/feed_status',           :to => 'feed#status'
    get  '/crm/pipelines',             :to => 'pipelines#index', :as => 'api_pipelines'
    get  '/crm/health',                :to => 'health#show',     :as => 'api_health'
  end

  # ---------------------------------------------------------------- Browser (no format)
  scope :format => false do
    get '/crm', :to => 'dashboard#index', :as => 'dashboard'
    post '/crm/leads', :to => 'dashboard#create_lead', :as => 'leads'
    # Static segments before the :id routes, otherwise "board" resolves as an id.
    get  '/crm/deals/board',           :to => 'deals#board',   :as => 'deals_board'
    %w(accounts contacts deals activities).each do |type|
      get   "/crm/#{type}",                 :to => "#{type}#index",   :as => type
      get   "/crm/#{type}/new",             :to => "#{type}#new",     :as => "new_#{type.singularize}"
      post  "/crm/#{type}",                 :to => "#{type}#create"
      get   "/crm/#{type}/:id",             :to => "#{type}#show",    :as => type.singularize
      get   "/crm/#{type}/:id/edit",        :to => "#{type}#edit",    :as => "edit_#{type.singularize}"
      match "/crm/#{type}/:id",             :to => "#{type}#update",  :via => [:put, :patch]
      put   "/crm/#{type}/:id/archive",     :to => "#{type}#archive", :as => "archive_#{type.singularize}"
      put   "/crm/#{type}/:id/restore",     :to => "#{type}#restore", :as => "restore_#{type.singularize}"
      post  "/crm/#{type}/bulk",            :to => "#{type}#bulk",    :as => "bulk_#{type}"
    end
    put  '/crm/deals/:id/move',        :to => 'deals#move',    :as => 'move_deal'
    get  '/crm/accounts/:id/merge',    :to => 'merges#new',    :defaults => {:record_type => 'account'}, :as => 'merge_account'
    post '/crm/accounts/:id/merge',    :to => 'merges#create', :defaults => {:record_type => 'account'}
    get  '/crm/contacts/:id/merge',    :to => 'merges#new',    :defaults => {:record_type => 'contact'}, :as => 'merge_contact'
    post '/crm/contacts/:id/merge',    :to => 'merges#create', :defaults => {:record_type => 'contact'}
    post '/crm/accounts/:id/links',    :to => 'links#create',  :defaults => {:record_type => 'account'}, :as => 'account_links'
    post '/crm/contacts/:id/links',    :to => 'links#create',  :defaults => {:record_type => 'contact'}, :as => 'contact_links'
    post '/crm/deals/:id/links',       :to => 'links#create',  :defaults => {:record_type => 'deal'}, :as => 'deal_links'
    delete '/crm/links/:id',           :to => 'links#destroy', :as => 'link'
    post '/crm/accounts/:id/projects', :to => 'account_projects#create', :as => 'account_projects'
    delete '/crm/accounts/:id/projects/:project_id', :to => 'account_projects#destroy', :as => 'account_project'
    get  '/crm/health',                :to => 'health#show',   :as => 'health'

    # Saved views (global Query rows) — thin plugin controller reusing core partials.
    get    '/crm/queries/new',      :to => 'queries#new',     :as => 'new_query'
    post   '/crm/queries',          :to => 'queries#create',  :as => 'queries'
    get    '/crm/queries/:id/edit', :to => 'queries#edit',    :as => 'edit_query'
    match  '/crm/queries/:id',      :to => 'queries#update',  :via => [:put, :patch], :as => 'query'
    delete '/crm/queries/:id',      :to => 'queries#destroy'

    # Administration (require_admin)
    get   '/crm/admin/pipelines',                  :to => 'pipelines#index',  :as => 'pipelines'
    post  '/crm/admin/pipelines',                  :to => 'pipelines#create'
    match '/crm/admin/pipelines/:id',              :to => 'pipelines#update', :via => [:put, :patch], :as => 'pipeline'
    delete '/crm/admin/pipelines/:id',             :to => 'pipelines#destroy'
    post  '/crm/admin/pipelines/:id/stages',       :to => 'stages#create',    :as => 'pipeline_stages'
    match '/crm/admin/stages/:id',                 :to => 'stages#update',    :via => [:put, :patch], :as => 'stage'
    delete '/crm/admin/stages/:id',                :to => 'stages#destroy'
  end
end
