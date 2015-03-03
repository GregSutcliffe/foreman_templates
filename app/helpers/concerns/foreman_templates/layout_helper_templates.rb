module ForemanTemplates::LayoutHelperTemplates
  extend ActiveSupport::Concern

  included do
    alias_method_chain :title_actions, :templates
  end

  def title_actions_with_templates(*args)
    # This is hacky, but the config_templates view doesn't have it's own helper to add to...
    url_options = {:only_path => true, :controller => 'foreman_templates/templates', :action => 'import'}
    if controller_name == "config_templates" && User.current.allowed_to?(url_options)
      url_hash = ForemanTemplates::Engine.routes.url_for(url_options)
      args << link_to(_('Import Templates'), url_hash, :class=>'btn')
    end
    title_actions_without_templates(*args)
  end

end
