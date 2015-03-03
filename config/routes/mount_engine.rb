Foreman::Application.routes.draw do
  mount ForemanTemplates::Engine, :at => "/templates"
end
