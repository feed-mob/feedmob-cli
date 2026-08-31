# frozen_string_literal: true

require 'dry/cli'
require_relative 'commands/auth'
require_relative 'commands/doctor'
require_relative 'commands/pages'
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
          request.register 'put', TimeOffRequestPut
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
      register 'pages' do |pages|
        pages.register 'auth' do |auth|
          auth.register 'login', PagesAuthLogin
          auth.register 'status', PagesAuthStatus
          auth.register 'logout', PagesAuthLogout
        end
        pages.register 'list', PagesList
        pages.register 'show', PagesShow
        pages.register 'stats', PagesStats
        pages.register 'publish', PagesPublish
        pages.register 'update', PagesUpdate
        pages.register 'share' do |share|
          share.register 'enable', PagesShareEnable
          share.register 'revoke', PagesShareRevoke
        end
        pages.register 'asset' do |asset|
          asset.register 'upload', PagesAssetUpload
        end
        pages.register 'request' do |request|
          request.register 'get', PagesRequestGet
        end
      end
    end
  end
end
