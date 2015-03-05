ForemanTemplates::Engine.routes.draw do
  resources :templates, :only => [] do
    get  'import',           :on => :collection
    post 'obsolete_and_new', :on => :collection
  end
end
