require 'foreman_templates'
require 'diffy'

module ForemanTemplates
  #Inherit from the Rails module of the parent app (Foreman), not the plugin.
  #Thus, inhereits from ::Rails::Engine and not from Rails::Engine
  class Engine < ::Rails::Engine
    isolate_namespace ForemanTemplates

    config.autoload_paths += Dir["#{config.root}/app/helpers/concerns"]

    initializer 'foreman_templates.mount_engine', :after=> :build_middleware_stack do |app|
      app.routes_reloader.paths << "#{ForemanTemplates::Engine.root}/config/routes/mount_engine.rb"
    end

    initializer 'foreman_templates.register_plugin', :after=> :finisher_hook do |app|
      Foreman::Plugin.register :foreman_templates do
        requires_foreman '>= 1.7'
        security_block :bootdisk do |map|
          permission :import_templates, {:'foreman_templates/templates' => [:import]}
        end

        role "Import templates from git", [:import_templates]

      end
    end

    config.to_prepare do
      begin
        LayoutHelper.send(:include, ForemanTemplates::LayoutHelperTemplates)
      rescue => e
        puts "ForemanTemplates: skipping engine hook (#{e.to_s})"
      end
    end

    rake_tasks do
      load "templates.rake"
    end

  end
end
