module ForemanTemplates
  class Importer

    def initialize(args = { })
      @verbose = args[:verbose] || false
      @repo    = args[:repo] || 'https://github.com/theforeman/community-templates.git'
      @branch  = args[:branch] || ''
      @prefix  = args[:prefix] || nil
      @dirname = args[:dirname] || '/'
      @filter  = args[:filter] || nil

      @db_templates     = {}
      @loaded_templates = {}
    end

    def changes
      changes = { 'new' => { }, 'obsolete' => { }, 'updated' => { } }

      new     = new_templates
      old     = removed_templates
      updated = updated_templates
      changes['new'] = new if new.any?
      changes['obsolete'] = old if old.any?
      changes['updated'] = updated if updated.any?

      changes
    end

    # Update the templates based upon the user's selection
    # It does a best attempt and can fail to perform all operations due to the
    # user requesting impossible selections. Repeat the operation if errors are
    # shown, after fixing the request.
    # +changed+ : Hash with three keys: :new, :updated and :obsolete.
    #               changed[:/new|updated|obsolete/] is an Array of Strings
    # Returns   : Array of Strings containing all record errors
    def obsolete_and_new(changes = { })
      require 'pry' ; binding.pry
      return if changes.empty?
      changes.values.map(&:keys).flatten.uniq.each do |env_name|
        if changes['new'] and changes['new'][env_name].try(:>, '') # we got new classes
          add_classes_to_foreman(env_name, JSON.parse(changes['new'][env_name]))
        end
        if changes['obsolete'] and changes['obsolete'][env_name].try(:>, '') # we need to remove classes
          remove_classes_from_foreman(env_name, JSON.parse(changes['obsolete'][env_name]))
        end
        if changes['updated'] and changes['updated'][env_name].try(:>, '') # we need to update classes
          update_classes_in_foreman(env_name, JSON.parse(changes['updated'][env_name]))
        end
      end
      []
      #rescue => e
      #  logger.error(e)
      #  [e.to_s]
    end

    def new_templates
      HashWithIndifferentAccess[
        loaded_templates.map do |template,data|
          [template, { "new" => data }] unless db_template_names.include?(template)
        end.compact
      ]
    end

    def removed_templates
      HashWithIndifferentAccess[
        (db_template_names - loaded_templates.keys).map { |tpl| [tpl, { "delete" => "" }] }.compact
      ]
    end

    def updated_templates
      HashWithIndifferentAccess[
        db_templates.map do |db_template|
          compare_template(db_template)
        end.compact
      ]
    end

    # This method check if the puppet class exists in this environment, and compare the class params.
    # Changes in the params are categorized to new parameters, removed parameters and parameters with a new
    # default value.
    def compare_template(db_template)
      return nil unless (data = loaded_templates[db_template.name])
      changed = false
      if db_template.is_a? Ptable
        # Family metadata detection relies on the OS being present in the DB
        if data['metadata']['os_family'].present? && db_template.os_family != data['metadata']['os_family']
          changed = true
        end
        changed = true unless db_template.layout == data['text']
      else
        changed = true unless db_template.template_kind.try('name') == data['metadata']['kind']
        changed = true unless db_template.operatingsystems.map(&:id).sort == data['metadata']['os_ids']
        changed = true unless db_template.template == data['text']
      end
      return [db_template.name, data] if changed
      return nil
    end

    def db_templates
      return @db_templates if @db_templates.present?
      @db_templates = [ConfigTemplate.all + Ptable.all].flatten
    end

    def db_template_names
      db_templates.map(&:name)
    end

    def loaded_templates
      return @loaded_templates if @loaded_templates.present?
      # Clone the repo and build a fat hash of data
      begin
        dir     = Dir.mktmpdir
        command = "git clone #{@branch.present? ? "-b #{@branch}" : ''} #{@repo} #{dir}"
        status = `#{command}`
        Rails.logger.info "#{status}" if @verbose

        # Parse the template into hash entries
        Dir["#{dir}#{@dirname}/**/*.erb"].each do |template|
          metadata = read_metadata(template)
          next if metadata.nil?
          next if @filter and not metadata['name'].match(/#{filter}/i)

          @loaded_templates[metadata['name']] = metadata
        end
      rescue => e
        Rails.logger.info "TemplatesError: #{e.message}\n#{e.backtrace}"
      ensure
        FileUtils.remove_entry_secure(dir)
      end
      @loaded_templates
    end

    def read_metadata(path)
      text = File.read(path)

      # Pull out the first erb comment only - /m is for a multiline regex
      extracted = text.match(/<%\#(.+?).-?%>/m)
      return nil if extracted.nil?
      metadata = YAML.load(extracted[1])

      # Get the name
      filename = path.split('/').last
      title    = filename.split('.').first
      name     = metadata['name'] || title
      name     = [@prefix, name].compact.join(' ')

      metadata['os_ids'] = if metadata['oses']
                             metadata['oses'].map do |os|
                               db_oses.map { |db| db.to_label =~ /^#{os}/ ? db.id : nil}
                             end.flatten.compact
                           else
                             []
                           end
      metadata['os_family'] = metadata['os_ids'].map { |id| Operatingsystem.find(id).family }.uniq.first

      return {
        'name'     => name,
        'text'     => text,
        'metadata' => metadata,
      }
    end

    def db_oses
      @db_oses || Operatingsystem.all
    end

  end
end
