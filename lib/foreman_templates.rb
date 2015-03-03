require 'foreman_templates/version'                  
module ForemanTemplates
  ENGINE_NAME = 'foreman_templates' 
  require 'foreman_templates/engine' if defined?(Rails) && Rails::VERSION::MAJOR == 3 
end 
