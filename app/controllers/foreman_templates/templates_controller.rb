module ForemanTemplates
  class TemplatesController < ::ApplicationController

    def import
      begin
        true
      rescue => e
        error _('Failed to render boot disk template: %s') % e
        redirect_to :back
        return
      end
    end

  end
end
