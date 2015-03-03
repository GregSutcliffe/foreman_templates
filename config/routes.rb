ForemanTemplates::Engine.routes.draw do
  resources :templates, :only => [] do
    get 'import', :on => :collection
  end
end
