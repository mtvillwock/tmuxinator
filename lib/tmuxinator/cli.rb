module Tmuxinator
  class Cli < Thor
    # By default, Thor returns exit(0) when an error occurs.
    # Please see: https://github.com/tmuxinator/tmuxinator/issues/192
    def self.exit_on_failure?
      true
    end

    include Tmuxinator::Util

    COMMANDS = {
      commands: "Lists commands available in tmuxinator",
      completions: "Used for shell completion",
      new: "Create a new project file and open it in your editor",
      edit: "Alias of new",
      open: "Alias of new",
      start: %w{
        Start a tmux session using a project's tmuxinator config,
        with an optional [ALIAS] for project reuse
      }.join(" "),
      stop: "Stop a tmux session using a project's tmuxinator config",
      local: "Start a tmux session using ./.tmuxinator.yml",
      debug: "Output the shell commands that are generated by tmuxinator",
      copy: %w{
        Copy an existing project to a new project and
        open it in your editor
      }.join(" "),
      delete: "Deletes given project",
      implode: "Deletes all tmuxinator projects",
      version: "Display installed tmuxinator version",
      doctor: "Look for problems in your configuration",
      list: "Lists all tmuxinator projects"
    }

    package_name "tmuxinator" \
      unless Gem::Version.create(Thor::VERSION) < Gem::Version.create("0.18")

    desc "commands", COMMANDS[:commands]

    def commands(shell = nil)
      out = if shell == "zsh"
              COMMANDS.map do |command, desc|
                "#{command}:#{desc}"
              end.join("\n")
            else
              COMMANDS.keys.join("\n")
            end

      say out
    end

    desc "completions [arg1 arg2]", COMMANDS[:completions]

    def completions(arg)
      if %w(start stop edit open copy delete).include?(arg)
        configs = Tmuxinator::Config.configs
        say configs.join("\n")
      end
    end

    desc "new [PROJECT]", COMMANDS[:new]
    map "open" => :new
    map "edit" => :new
    map "o" => :new
    map "e" => :new
    map "n" => :new
    method_option :local, type: :boolean,
                          aliases: ["-l"],
                          desc: "Create local project file at ./.tmuxinator.yml"

    def new(name)
      project_file = find_project_file(name, options[:local])
      Kernel.system("$EDITOR #{project_file}") || doctor
    end

    no_commands do
      def find_project_file(name, local = false)
        path = if local
                 Tmuxinator::Config::LOCAL_DEFAULT
               else
                 Tmuxinator::Config.default_project(name)
               end
        if File.exist?(path)
          path
        else
          generate_project_file(name, path)
        end
      end

      def generate_project_file(name, path)
        template = Tmuxinator::Config.default? ? :default : :sample
        content = File.read(Tmuxinator::Config.send(template.to_sym))
        erb = Erubis::Eruby.new(content).result(binding)
        File.open(path, "w") { |f| f.write(erb) }
        path
      end

      def create_project(project_options = {})
        attach_opt = project_options[:attach]
        attach = !attach_opt.nil? && attach_opt ? true : false
        detach = !attach_opt.nil? && !attach_opt ? true : false

        options = {
          force_attach: attach,
          force_detach: detach,
          name: project_options[:name],
          custom_name: project_options[:custom_name],
          args: project_options[:args]
        }

        begin
          Tmuxinator::Config.validate(options)
        rescue => e
          exit! e.message
        end
      end

      def render_project(project)
        if project.deprecations.any?
          project.deprecations.each { |deprecation| say deprecation, :red }
          say
          print "Press ENTER to continue."
          STDIN.getc
        end

        Kernel.exec(project.render)
      end

      def kill_project(project)
        Kernel.exec(project.tmux_kill_session_command)
      end
    end

    desc "start [PROJECT] [ARGS]", COMMANDS[:start]
    map "s" => :start
    method_option :attach, type: :boolean,
                           aliases: "-a",
                           desc: "Attach to tmux session after creation."
    method_option :name, aliases: "-n",
                         desc: "Give the session a different name"

    def start(name, *args)
      params = {
        name: name,
        custom_name: options[:name],
        attach: options[:attach],
        args: args
      }
      project = create_project(params)
      render_project(project)
    end

    desc "stop [PROJECT]", COMMANDS[:stop]
    map "st" => :stop

    def stop(name)
      params = {
        name: name
      }
      project = create_project(params)
      kill_project(project)
    end

    desc "local", COMMANDS[:local]
    map "." => :local

    def local
      render_project(create_project(attach: options[:attach]))
    end

    method_option :attach, type: :boolean,
                           aliases: "-a",
                           desc: "Attach to tmux session after creation."
    method_option :name, aliases: "-n",
                         desc: "Give the session a different name"
    desc "debug [PROJECT] [ARGS]", COMMANDS[:debug]

    def debug(name, *args)
      params = {
        name: name,
        custom_name: options[:name],
        attach: options[:attach],
        args: args
      }
      project = create_project(params)
      say project.render
    end

    desc "copy [EXISTING] [NEW]", COMMANDS[:copy]
    map "c" => :copy
    map "cp" => :copy

    def copy(existing, new)
      existing_config_path = Tmuxinator::Config.project(existing)
      new_config_path = Tmuxinator::Config.project(new)

      exit!("Project #{existing} doesn't exist!") \
        unless Tmuxinator::Config.exists?(existing)

      new_exists = Tmuxinator::Config.exists?(new)
      question = "#{new} already exists, would you like to overwrite it?"
      if !new_exists || yes?(question, :red)
        say "Overwriting #{new}" if Tmuxinator::Config.exists?(new)
        FileUtils.copy_file(existing_config_path, new_config_path)
      end

      Kernel.system("$EDITOR #{new_config_path}")
    end

    desc "delete [PROJECT1] [PROJECT2] ...", COMMANDS[:delete]
    map "d" => :delete
    map "rm" => :delete

    def delete(*projects)
      projects.each do |project|
        if Tmuxinator::Config.exists?(project)
          config = Tmuxinator::Config.project(project)

          if yes?("Are you sure you want to delete #{project}?(y/n)", :red)
            FileUtils.rm(config)
            say "Deleted #{project}"
          end
        else
          say "#{project} does not exist!"
        end
      end
    end

    desc "implode", COMMANDS[:implode]
    map "i" => :implode

    def implode
      if yes?("Are you sure you want to delete all tmuxinator configs?", :red)
        FileUtils.remove_dir(Tmuxinator::Config.root)
        say "Deleted all tmuxinator projects."
      end
    end

    desc "list", COMMANDS[:list]
    map "l" => :list
    map "ls" => :list

    def list
      say "tmuxinator projects:"

      print_in_columns Tmuxinator::Config.configs
    end

    desc "version", COMMANDS[:version]
    map "-v" => :version

    def version
      say "tmuxinator #{Tmuxinator::VERSION}"
    end

    desc "doctor", COMMANDS[:doctor]

    def doctor
      say "Checking if tmux is installed ==> "
      yes_no Tmuxinator::Config.installed?

      say "Checking if $EDITOR is set ==> "
      yes_no Tmuxinator::Config.editor?

      say "Checking if $SHELL is set ==> "
      yes_no Tmuxinator::Config.shell?
    end
  end
end
