# frozen_string_literal: true

require 'dry/cli'
require_relative 'commands/auth'
require_relative 'commands/doctor'
require_relative 'commands/request'
require_relative 'commands/version'

module FeedMob
  module CLI
    module Commands
      extend Dry::CLI::Registry

      register 'doctor', Doctor
      register 'version', Version
      register 'pixel' do |pixel|
        pixel.register 'auth' do |auth|
          auth.register 'login', PixelAuthLogin
          auth.register 'status', PixelAuthStatus
          auth.register 'logout', PixelAuthLogout
        end
        pixel.register 'request' do |request|
          request.register 'get', PixelRequestGet
        end
      end
      register 'time-off' do |time_off|
        time_off.register 'auth' do |auth|
          auth.register 'login', TimeOffAuthLogin
          auth.register 'status', TimeOffAuthStatus
          auth.register 'logout', TimeOffAuthLogout
        end
        time_off.register 'request' do |request|
          request.register 'get', TimeOffRequestGet
        end
      end
      register 'femini' do |femini|
        femini.register 'auth' do |auth|
          auth.register 'login', FeminiAuthLogin
          auth.register 'status', FeminiAuthStatus
          auth.register 'logout', FeminiAuthLogout
        end
        femini.register 'request' do |request|
          request.register 'get', FeminiRequestGet
        end
      end
    end
  end
end
