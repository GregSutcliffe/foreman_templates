module ForemanTemplates
  class Importer

    def initialize(args = { })
      @verbose = args[:verbose] || false
      @repo    = args[:repo] || 'https://github.com/theforeman/community-templates.git'
      @branch  = args[:branch] || ''
      @prefix  = args[:prefix] || nil
      @dirname = args[:dirname] || '/'
      @filter  = args[:filter] || nil

      @loaded_templates = []
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
      return if changes.empty?
      if changes['obsolete'] # we need to remove templates
        remove_templates_from_foreman(changes['obsolete'])
      end
      if changes['new'] # we got new templates
        add_templates_to_foreman(changes['new'])
      end
      if changes['updated'] # we need to update templates
        update_templates_in_foreman(changes['updated'])
      end
      []
      #rescue => e
      #  logger.error(e)
      #  [e.to_s]
    end


    private

    # git repo parsing methods

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

          @loaded_templates << metadata
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
                               Operatingsystem.all.map { |db| db.to_label =~ /^#{os}/ ? db.id : nil}
                             end.flatten.compact
                           else
                             []
                           end
      metadata['os_family'] = metadata['os_ids'].map { |id| Operatingsystem.find(id).family }.uniq.first

      metadata['name'] = name
      metadata['text'] = text

      return metadata
    end

    # change detection methods

    def db_templates
      [ConfigTemplate.includes(:template_kind).all + Ptable.all].flatten
    end

    def new_templates
      HashWithIndifferentAccess[
        loaded_templates.map do |data|
          [data['name'], data] unless db_templates.map(&:name).include?(data['name'])
        end.compact
      ]
    end

    def removed_templates
      # Need to get the kind from the DB since by definition it's not in the git repo
      HashWithIndifferentAccess[
        db_templates.map do |db_tpl|
          next if loaded_templates.map {|t| t['name'] }.include?(db_tpl.name)
          kind = if db_tpl.is_a?(ConfigTemplate)
                   if db_tpl.snippet?
                     'snippet'
                   else
                     db_tpl.template_kind.name
                   end
                 else
                   'ptable' if db_tpl.is_a?(Ptable)
                 end
          [db_tpl.name, { 'name' => db_tpl.name, 'kind' => kind }]
        end.compact
      ]
    end

    def updated_templates
      HashWithIndifferentAccess[
        loaded_templates.map do |data|
          compare_template(data)
        end.compact
      ]
    end

    # This method builds a diff of the potential changes in between the db and the repo
    # There's a lot of string-casting so that Diffy can generate the right diffs for
    # the Ace JS to display in the modal window.
    def compare_template(data)
      db_tpl = case data['kind']
                when 'ptable'
                  Ptable.find_by_name(data['name'])
                when 'snippet'
                  ConfigTemplate.where(:snippet => true).find_by_name(data['name'])
                else
                  tkid = TemplateKind.find_by_name(data['kind']).id
                  ConfigTemplate.where(:template_kind_id => tkid).find_by_name(data['name'])
                end
      return nil unless db_tpl.present?

      # Build an array of things that changed so we can display it to the user
      changed = []
      if db_tpl.is_a? Ptable
        # Family metadata detection relies on the OS being present in the DB
        if data['os_family'].present? && db_tpl.os_family != data['os_family']
          changed << "OS family changed"
          changed << Diffy::Diff.new("#{db_tpl.os_family}\n", "#{data['os_family']}\n").to_s
        end
        unless db_tpl.layout == data['text']
          changed << "Template changes"
          changed << Diffy::Diff.new(db_tpl.layout, data['text']).to_s
        end
      else
        unless db_tpl.operatingsystems.map(&:id).sort == data['os_ids']
          changed << 'Operatingsystem associations'
          new_os = Operatingsystem.where(:id => data['os_ids']).sort.map(&:title).join("\n")
          db_os  = db_tpl.operatingsystems.map(&:title).join("\n")
          changed << Diffy::Diff.new("#{db_os}\n", "#{new_os}\n").to_s
        end
        unless db_tpl.template == data['text']
          changed << "Template changes"
          changed << Diffy::Diff.new(db_tpl.template, data['text']).to_s
        end
      end
      if changed.present?
        data['diff'] = ["---",changed].flatten.join("\n")
        return [data['name'], data]
      end
      return nil
    end


    # creation/deletion methods

    def remove_templates_from_foreman(templates)
      templates.select{|v| v['kind'] == 'ptable'}.each do |data|
        Ptable.find_by_name(data['name']).destroy
      end
      templates.reject{|v| v['kind'] == 'ptable'}.each do |data|
        ConfigTemplate.find_by_name(data['name']).destroy
      end
    end

    def add_templates_to_foreman(templates)
      templates.select{|v| v['kind'] == 'ptable'}.each do |data|
        pt = Ptable.new(
          :name      => data['name'],
          :layout    => data['text'],
          :os_family => data['os_family']
        )
        pt.save
      end
      templates.reject{|v| v['kind'] == 'ptable'}.each do |data|
        snippet = data['kind'] == "snippet" ? true : false
        ct = ConfigTemplate.new(
          :name                => data['name'],
          :template            => data['text'],
          :snippet             => snippet,
          :operatingsystem_ids => data['os_ids'],
          :template_kind       => TemplateKind.find_by_name(data['kind'])
        )
        ct.save
      end
    end

    def update_templates_in_foreman(templates)
      templates.select{|v| v['kind'] == 'ptable'}.each do |data|
        pt = Ptable.find_by_name(data['name']).update_attributes({
          :layout    => data['text'],
          :os_family => data['os_family'],
        })
      end
      templates.reject{|v| v['kind'] == 'ptable'}.each do |data|
        snippet = data['kind'] == "snippet" ? true : false
        ct = ConfigTemplate.find_by_name(data['name']).update_attributes({
          :template            => data['text'],
          :snippet             => snippet,
          :operatingsystem_ids => data['os_ids'],
          :template_kind       => TemplateKind.find_by_name(data['kind'])
        })
      end
    end

  end
end
