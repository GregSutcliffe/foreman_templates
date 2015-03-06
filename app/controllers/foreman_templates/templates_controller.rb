module ForemanTemplates
  class TemplatesController < ::ApplicationController

    def import
      begin
        opts = {}
        @importer  = ForemanTemplates::Importer.new(opts)
        @changed  = @importer.changes
      rescue => e
        raise e
      end

      if @changed["new"].size > 0 or @changed["obsolete"].size > 0 or @changed["updated"].size > 0
        render "_templates_changed"
      else
        notice _("No changes to your templates detected")
        #redirect_to :controller => main_app.config_templates_path  - doesn't work :(
        redirect_to '/config_templates'
      end
    end

    def obsolete_and_new
      unless params[:changed].present?
        notice _("No changes to your templates selected")
      else
        changed = {}
        ['new','obsolete','updated'].each do |section|
          next if params[:changed][section].empty?
          changed[section] = []
          params[:changed][section].each { |k,v| changed[section] << JSON.parse(v) }
        end

        if (errors = ::ForemanTemplates::Importer.new.obsolete_and_new(changed)).empty?
          notice _("Successfully updated templates from the git repo")
        else
          error _("Failed to update templates from the git repo: %s") % errors.to_sentence
        end
      end
      #redirect_to :controller => main_app.config_templates_path  - doesn't work :(
      redirect_to '/config_templates'
    end

  end
end
