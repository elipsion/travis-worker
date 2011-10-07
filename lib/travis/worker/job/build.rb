require "travis/worker/job/base"

module Travis
  module Worker

    module Job
      # Build job implementation that uses the following workflow:
      #
      # * Clones/fetches the repository from {https://github.com GitHub}
      # * Installs dependencies
      # * Switches to the default or specified language implementation
      # * Runs one or more build scripts
      #
      # @see Base
      # @see Worker::Config
      class Build < Base

        # Build exit status
        # @return [Integer] 0 for success, 1 otherwise
        attr_reader :status

        # Output that was collected during build run
        # @return [String]
        attr_reader :log

        def initialize(payload, virtual_machine)
          super
          @log = ''
          repository.shell = shell
          setup_shell_logging
        end

        def start
          payload = reporting_payload({
            :started_at => Time.now,
            :queue => Travis::Worker.config.queue
          })
          notify(:start, payload)
          update(:log => "Using worker: #{worker_name}\n\n")
        end

        def update(data)
          log << data[:log] if data.key?(:log)
          payload = reporting_payload(data)
          notify(:update, payload)
        end

        def finish
          payload = reporting_payload({
            :log => log,
            :status => status,
            :finished_at => Time.now
          })
          notify(:finish, payload)
          shell.close if shell.open?
        end

        protected

          def worker_name
            "#{Travis::Worker.hostname}:#{virtual_machine.name}"
          end

          def shell
            virtual_machine.shell
          end

          def setup_shell_logging
            shell.on_output do |data|
              announce(data)
              update(:log => data)
            end
          end

          def perform
            @status = build! ? 0 : 1
            sleep(2) # TODO hrmmm ...
          rescue
            @status = 1
            update(:log => "#{$!.class.name}: #{$!.message}\n#{$@.join("\n")}")
          ensure
            update(:log => "\nDone. Build script exited with: #{status}\n")
          end

          def build!
            virtual_machine.sandboxed do
              shell.connect
              create_builds_directory && checkout_repository && run_build
              shell.close
            end
          end

          def create_builds_directory
            shell.execute("mkdir -p #{self.class.base_dir}; cd #{self.class.base_dir}", :echo => false)
          end

          def run_build
            builder = Travis::Worker::Builder.create(build.config)
            announce("Using #{builder.inspect}")
            commands = builder::Commands.new(build.config, shell)
            commands.run
          end

          def checkout_repository
            repository.checkout(build.commit)
          end
      end

    end
  end
end
