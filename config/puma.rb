# frozen_string_literal: true

require "fileutils"
#require 'puma/acme'

discourse_path = File.expand_path(File.expand_path(File.dirname(__FILE__)) + "/../")

enable_logstash_logger = ENV["ENABLE_LOGSTASH_LOGGER"] == "1"
puma_stderr_path = "#{discourse_path}/log/puma.stderr.log"
puma_stdout_path = "#{discourse_path}/log/puma.stdout.log"

# Load logstash logger if enabled
if enable_logstash_logger
  require_relative "../lib/discourse_logstash_logger"
  FileUtils.touch(puma_stderr_path) if !File.exist?(puma_stderr_path)
  # Note: You may need to adapt the logger initialization for Puma
  log_formatter =
    proc do |severity, time, progname, msg|
      event = {
        "@timestamp" => Time.now.utc,
        "message" => msg,
        "severity" => severity,
        "type" => "puma",
      }
      "#{event.to_json}\n"
    end
else
  stdout_redirect puma_stdout_path, puma_stderr_path, true
end

# Number of workers (processes)
workers ENV.fetch("PUMA_WORKERS", 6).to_i

# Set the directory
directory discourse_path

# Bind to the specified address and port
bind ENV.fetch(
       "PUMA_BIND",
       "tcp://#{ENV["PUMA_BIND_ALL"] ? "" : "127.0.0.1:"}#{ENV.fetch("PUMA_PORT", 3000)}",
     )
#bind 'tcp://0.0.0.0:80'
#plugin :acme
#acme_server_name 'xjtu.app'
#acme_tos_agreed true
#bind 'acme://0.0.0.0:443'

# PID file location
FileUtils.mkdir_p("#{discourse_path}/tmp/pids")
pidfile ENV.fetch("PUMA_PID_PATH", "#{discourse_path}/tmp/pids/puma.pid")

# State file - used by pumactl
state_path "#{discourse_path}/tmp/pids/puma.state"

# Environment-specific configuration
if ENV["RAILS_ENV"] == "production"
  # Production timeout
  worker_timeout 30
else
  # Development timeout
  worker_timeout ENV.fetch("PUMA_TIMEOUT", 60).to_i
end

# Preload application
preload_app!

# Handle worker boot and shutdown
before_fork do
  Discourse.preload_rails!
  Discourse.before_fork

  # Supervisor check
  supervisor_pid = ENV["PUMA_SUPERVISOR_PID"].to_i
  if supervisor_pid > 0
    Thread.new do
      loop do
        unless File.exist?("/proc/#{supervisor_pid}")
          puts "Kill self supervisor is gone"
          Process.kill "TERM", Process.pid
        end
        sleep 2
      end
    end
  end

  # Sidekiq workers
  sidekiqs = ENV["PUMA_SIDEKIQS"].to_i
  if sidekiqs > 0
    puts "starting #{sidekiqs} supervised sidekiqs"

    require "demon/sidekiq"
    Demon::Sidekiq.after_fork { DiscourseEvent.trigger(:sidekiq_fork_started) }
    Demon::Sidekiq.start(sidekiqs)

    if Discourse.enable_sidekiq_logging?
      Signal.trap("USR1") do
        # Delay Sidekiq log reopening
        sleep 1
        Demon::Sidekiq.kill("USR2")
      end
    end
  end

  # Email sync demon
  if ENV["DISCOURSE_ENABLE_EMAIL_SYNC_DEMON"] == "true"
    puts "starting up EmailSync demon"
    Demon::EmailSync.start(1)
  end

  # Plugin demons
  DiscoursePluginRegistry.demon_processes.each do |demon_class|
    puts "starting #{demon_class.prefix} demon"
    demon_class.start(1)
  end

  # Demon monitoring thread
  Thread.new do
    loop do
      begin
        sleep 60

        if sidekiqs > 0
          Demon::Sidekiq.ensure_running
          Demon::Sidekiq.heartbeat_check
          Demon::Sidekiq.rss_memory_check
        end

        if ENV["DISCOURSE_ENABLE_EMAIL_SYNC_DEMON"] == "true"
          Demon::EmailSync.ensure_running
          Demon::EmailSync.check_email_sync_heartbeat
        end

        DiscoursePluginRegistry.demon_processes.each(&:ensure_running)
      rescue => e
        Rails.logger.warn(
          "Error in demon processes heartbeat check: #{e}\n#{e.backtrace.join("\n")}",
        )
      end
    end
  end

  # Close Redis connection
  Discourse.redis.close
end

on_worker_boot do
  DiscourseEvent.trigger(:web_fork_started)
  Discourse.after_fork
end

# Worker timeout handling
worker_timeout 30

# Low-level worker options
threads 8, 32
