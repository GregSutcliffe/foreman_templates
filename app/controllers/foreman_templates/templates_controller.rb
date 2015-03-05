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
        redirect_to :controller => controller_path
      end
    end

    def obsolete_and_new
      if (errors = ::ForemanTemplates::Importer.new.obsolete_and_new(params[:changed])).empty?
        notice _("Successfully updated environments and Puppet classes from the on-disk Puppet installation")
      else
        error _("Failed to update environments and Puppet classes from the on-disk Puppet installation: %s") % errors.to_sentence
      end
      redirect_to :controller => config_templates_path
    end

  end
end
