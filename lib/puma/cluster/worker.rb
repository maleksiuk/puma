# frozen_string_literal: true

module Puma
  class Cluster < Puma::Runner
    # This class is instantiated by the `Puma::Cluster` and represents a single
    # worker process.
    #
    # At the core of this class is running an instance of `Puma::Server` which
    # gets created via the `start_server` method from the `Puma::Runner` class
    # that this inherits from.
    class Worker < Puma::Runner
      attr_reader :index, :master

      def initialize(index:, master:, launcher:, pipes:, server: nil)
        super launcher, launcher.events

        @index = index
        @master = master
        @launcher = launcher
        @options = launcher.options
        @check_pipe = pipes[:check_pipe]
        @worker_write = pipes[:worker_write]
        @fork_pipe = pipes[:fork_pipe]
        @wakeup = pipes[:wakeup]
        @server = server
      end

      def run
        title  = "puma: cluster worker #{index}: #{master}"
        title += " [#{@options[:tag]}]" if @options[:tag] && !@options[:tag].empty?
        $0 = title

        Signal.trap "SIGINT", "IGNORE"
        Signal.trap "SIGCHLD", "DEFAULT"

        Thread.new do
          Puma.set_thread_name "worker check pipe"
          IO.select [@check_pipe]
          log "! Detected parent died, dying"
          exit! 1
        end

        # If we're not running under a Bundler context, then
        # report the info about the context we will be using
        if !ENV['BUNDLE_GEMFILE']
          if File.exist?("Gemfile")
            log "+ Gemfile in context: #{File.expand_path("Gemfile")}"
          elsif File.exist?("gems.rb")
            log "+ Gemfile in context: #{File.expand_path("gems.rb")}"
          end
        end

        # Invoke any worker boot hooks so they can get
        # things in shape before booting the app.
        @launcher.config.run_hooks :before_worker_boot, index, @launcher.events

        server = @server ||= start_server
        restart_server = Queue.new << true << false

        fork_worker = @options[:fork_worker] && index == 0

        if fork_worker
          restart_server.clear
          worker_pids = []
          Signal.trap "SIGCHLD" do
            wakeup! if worker_pids.reject! do |p|
              Process.wait(p, Process::WNOHANG) rescue true
            end
          end

          Thread.new do
            Puma.set_thread_name "worker fork pipe"
            while (idx = @fork_pipe.gets)
              idx = idx.to_i
              if idx == -1 # stop server
                if restart_server.length > 0
                  restart_server.clear
                  server.begin_restart(true)
                  @launcher.config.run_hooks :before_refork, nil, @launcher.events
                  Puma::Util.nakayoshi_gc @events if @options[:nakayoshi_fork]
                end
              elsif idx == 0 # restart server
                restart_server << true << false
              else # fork worker
                worker_pids << pid = spawn_worker(idx)
                @worker_write << "f#{pid}:#{idx}\n" rescue nil
              end
            end
          end
        end

        Signal.trap "SIGTERM" do
          @worker_write << "e#{Process.pid}\n" rescue nil
          server.stop
          restart_server << false
        end

        begin
          @worker_write << "b#{Process.pid}:#{index}\n"
        rescue SystemCallError, IOError
          Thread.current.purge_interrupt_queue if Thread.current.respond_to? :purge_interrupt_queue
          STDERR.puts "Master seems to have exited, exiting."
          return
        end

        Thread.new(@worker_write) do |io|
          Puma.set_thread_name "stat payload"

          while true
            sleep Const::WORKER_CHECK_INTERVAL
            begin
              require 'json'
              io << "p#{Process.pid}#{server.stats.to_json}\n"
            rescue IOError
              Thread.current.purge_interrupt_queue if Thread.current.respond_to? :purge_interrupt_queue
              break
            end
          end
        end

        server.run.join while restart_server.pop

        # Invoke any worker shutdown hooks so they can prevent the worker
        # exiting until any background operations are completed
        @launcher.config.run_hooks :before_worker_shutdown, index, @launcher.events
      ensure
        @worker_write << "t#{Process.pid}\n" rescue nil
        @worker_write.close
      end

      private

      def spawn_worker(idx)
        @launcher.config.run_hooks :before_worker_fork, idx, @launcher.events

        pid = fork do
          new_worker = Worker.new index: idx,
                                  master: master,
                                  launcher: @launcher,
                                  pipes: { check_pipe: @check_pipe,
                                           worker_write: @worker_write },
                                  server: @server
          new_worker.run
        end

        if !pid
          log "! Complete inability to spawn new workers detected"
          log "! Seppuku is the only choice."
          exit! 1
        end

        @launcher.config.run_hooks :after_worker_fork, idx, @launcher.events
        pid
      end

      def wakeup!
        return unless @wakeup

        begin
          @wakeup.write "!" unless @wakeup.closed?
        rescue SystemCallError, IOError
          Thread.current.purge_interrupt_queue if Thread.current.respond_to? :purge_interrupt_queue
        end
      end
    end
  end
end
