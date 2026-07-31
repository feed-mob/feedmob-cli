# frozen_string_literal: true

require 'io/console'
require_relative 'credentials'
require_relative 'http/client'
require_relative 'services'

module FeedMob
  module CLI
    class Runtime
      def initialize(env: ENV, credentials: nil, client_factory: nil, input: $stdin, output: $stdout)
        @env = env
        @credentials = credentials || Credentials.new(env:)
        @client_factory = client_factory || ->(service) { HTTP::Client.new(service:) }
        @input = input
        @output = output
      end

      attr_reader :credentials

      def service(name)
        Services.fetch(name, env: @env)
      end

      def services
        Services.all(env: @env)
      end

      def client(service)
        @client_factory.call(service)
      end

      def read_token_from_stdin
        token = @input.read.to_s.strip
        return token unless token.empty?

        raise Error.new(code: 'missing_token', message: 'No token was provided on standard input.')
      end

      def read_token_interactively(service)
        unless @input.respond_to?(:tty?) && @input.tty?
          raise Error.new(
            code: 'interactive_input_unavailable',
            message: "Interactive input is unavailable. Pipe the token with --token-stdin or set #{service.token_env}."
          )
        end

        @output.print("#{service.label} token: ")
        @output.flush
        token = @input.noecho(&:gets).to_s.strip
        @output.puts
        return token unless token.empty?

        raise Error.new(code: 'missing_token', message: 'No token was entered.')
      end
    end
  end
end
