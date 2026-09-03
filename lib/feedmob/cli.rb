# frozen_string_literal: true

require 'dry/cli'
require_relative 'cli/error'
require_relative 'cli/output'
require_relative 'cli/runtime'
require_relative 'cli/registry'
require_relative 'cli/version'

module FeedMob
  module CLI
    module_function

    def runtime
      @runtime ||= Runtime.new
    end

    def runtime=(value)
      @runtime = value
    end

    def json?
      Thread.current[:feedmob_cli_json] == true
    end

    def start(argv = ARGV, stdout: $stdout, stderr: $stderr)
      arguments = argv.dup
      json = !arguments.delete('--json').nil?
      previous_json = Thread.current[:feedmob_cli_json]
      Thread.current[:feedmob_cli_json] = json

      if arguments.empty? || arguments == ['--help'] || arguments == ['-h']
        stdout.puts <<~HELP
          FeedMob CLI

          Usage:
            fm [--json] COMMAND

          Commands:
            doctor                  Check configuration and service authentication
            version                 Print the fm version
            femini [SUBCOMMAND]     Work with Femini
            pages [SUBCOMMAND]      Work with FeedMob Pages
            pixel [SUBCOMMAND]      Work with FeedMob Pixel
            time-off [SUBCOMMAND]   Work with FeedMob Time Off
            workspace [SUBCOMMAND]  Work with FeedMob Workspace
        HELP
        return 0
      end

      Dry::CLI.new(Commands).call(arguments:, out: stdout, err: stderr)
      0
    rescue Error => e
      Output.new(stdout:, stderr:, json:).error(
        code: e.code,
        message: e.message,
        details: e.details
      )
      e.exit_status
    ensure
      Thread.current[:feedmob_cli_json] = previous_json if defined?(previous_json)
    end
  end
end
