# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'uri'
require_relative 'base'

module FeedMob
  module CLI
    module Commands
      class PagesBase < Base
        private

        def service_name = 'pages'

        def pages_request(method:, path:, message:, **request_options)
          credential = credential!(service)
          arguments = {
            method:,
            path:,
            token: credential.value
          }
          arguments.merge!(request_options)
          response = runtime.client(service).request(**arguments)
          output.success(
            { service: service.name, status: response.status, response: pages_response(response.data) },
            message:
          )
        end

        def pages_response(data)
          return data unless data.is_a?(Hash) && data.key?('code')
          return data.fetch('data', {}) if data['code'].to_s == '0'

          raise Error.new(
            code: data['code'].to_s.empty? ? 'pages_api_error' : data['code'].to_s,
            message: data['msg'] || data['message'] || 'Pages API returned an error.'
          )
        end

        def query_path(path, parameters)
          values = parameters.compact
          return path if values.empty?

          "#{path}?#{URI.encode_www_form(values)}"
        end

        def path_segment(value, label)
          URI::DEFAULT_PARSER.escape(required_value(value, label), /[^a-zA-Z0-9\-._~]/)
        end

        def required_value(value, label)
          string = value.to_s
          raise Error.new(code: 'invalid_input', message: "#{label} is required.") if string.empty?

          string
        end

        def page_id(value)
          string = value.to_s
          return string if string.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)

          raise Error.new(code: 'invalid_input', message: 'page_id must be a UUID.')
        end

        def read_text_file(path, label)
          file = required_file(path, label)
          File.binread(file)
        rescue Errno::EACCES
          raise Error.new(code: 'invalid_input', message: "#{label} cannot be read.")
        end

        def read_json_file(path, label, expected: nil)
          value = JSON.parse(read_text_file(path, label))
          return value if expected.nil? || value.is_a?(expected)

          raise Error.new(code: 'invalid_input', message: "#{label} has an invalid JSON shape.")
        rescue JSON::ParserError
          raise Error.new(code: 'invalid_input', message: "#{label} must contain valid JSON.")
        end

        def required_file(path, label)
          file = path.to_s
          unless !file.empty? && File.file?(file)
            raise Error.new(code: 'invalid_input', message: "#{label} must name a readable file.")
          end

          file
        end

        def optional_payload(**options)
          visibility = options[:visibility]
          validate_visibility!(visibility)
          payload = {
            title: options[:title],
            description: options[:description],
            tags: options[:tags],
            visibility:,
            data_sources: options[:data_sources_file] && read_json_file(
              options[:data_sources_file], 'data_sources file', expected: Hash
            ),
            files: options[:files_file] && read_json_file(options[:files_file], 'files file', expected: Array)
          }
          payload.compact
        end

        def validate_visibility!(visibility)
          return if visibility.nil? || %w[everyone unlisted].include?(visibility)

          raise Error.new(code: 'invalid_input', message: 'visibility must be everyone or unlisted.')
        end
      end

      class PagesList < PagesBase
        desc 'List or search Pages'
        option :page, type: :integer, desc: 'One-based page number'
        option :page_size, type: :integer, desc: 'Items per page (1-100)'
        option :q, type: :string, desc: 'Search keyword'
        option :scope, type: :string, desc: 'all, mine, or unassigned'
        option :tag, type: :string, desc: 'Subject tag'
        option :created_range, type: :string, desc: 'all, 24h, 7d, or 30d'
        option :submitter, type: :string, desc: 'Legacy submitter email'
        option :user_email, type: :string, desc: 'Bound owner email'
        option :user_id, type: :string, desc: 'Bound Google user ID'

        def call(**options)
          pages_request(
            method: :get,
            path: query_path('/api/pages', list_parameters(options)),
            message: 'Listed Pages.'
          )
        end

        private

        def list_parameters(options)
          {
            page: options[:page],
            page_size: options[:page_size],
            q: options[:q],
            scope: options[:scope],
            tag: options[:tag],
            created_range: options[:created_range],
            submitter: options[:submitter],
            user_email: options[:user_email],
            user_id: options[:user_id]
          }
        end
      end

      class PagesShow < PagesBase
        desc 'Show a published Page by owner and slug'
        argument :owner, required: true, desc: 'Page owner'
        argument :slug, required: true, desc: 'Page slug'

        def call(owner:, slug:, **)
          pages_request(
            method: :get,
            path: "/api/pages/#{path_segment(owner, 'owner')}/#{path_segment(slug, 'slug')}",
            message: 'Fetched Page.'
          )
        end
      end

      class PagesStats < PagesBase
        desc 'Show Pages site statistics'

        def call(**)
          pages_request(method: :get, path: '/api/pages/stats', message: 'Fetched Pages statistics.')
        end
      end

      class PagesPublish < PagesBase
        desc 'Publish an HTML Page'
        option :owner, type: :string, desc: 'Required page owner'
        option :html_file, type: :string, desc: 'Required HTML file'
        option :title, type: :string, desc: 'Display title'
        option :description, type: :string, desc: 'Page description'
        option :tags, type: :array, desc: 'Comma-separated subject tags'
        option :visibility, type: :string, desc: 'everyone or unlisted'
        option :data_sources_file, type: :string, desc: 'JSON object file for data_sources'
        option :files_file, type: :string, desc: 'JSON array file for multi-file assets'

        def call(**options)
          payload = optional_payload(**options)
          payload[:owner] = required_value(options[:owner], 'owner')
          payload[:html] = read_text_file(options[:html_file], 'html_file')
          pages_request(method: :post, path: '/api/pages', json: payload, message: 'Published Page.')
        end
      end

      class PagesUpdate < PagesBase
        desc 'Update a Page without changing its URL'
        argument :page_id, required: true, desc: 'Page UUID'
        option :html_file, type: :string, desc: 'Replacement HTML file'
        option :edits_file, type: :string, desc: 'JSON array file of find/replace edits'
        option :title, type: :string, desc: 'Display title'
        option :description, type: :string, desc: 'Page description'
        option :tags, type: :array, desc: 'Comma-separated replacement tags'
        option :visibility, type: :string, desc: 'everyone or unlisted'
        option :data_sources_file, type: :string, desc: 'JSON object file for data_sources'
        option :files_file, type: :string, desc: 'JSON array file for multi-file assets'

        def call(**options)
          if options[:html_file] && options[:edits_file]
            raise Error.new(code: 'invalid_input', message: 'html_file and edits_file cannot be used together.')
          end

          payload = optional_payload(**options)
          payload[:html] = read_text_file(options[:html_file], 'html_file') if options[:html_file]
          payload[:edits] = read_json_file(options[:edits_file], 'edits file', expected: Array) if options[:edits_file]
          raise Error.new(code: 'invalid_input', message: 'Provide at least one field to update.') if payload.empty?

          pages_request(
            method: :put,
            path: "/api/pages/#{page_id(options.fetch(:page_id))}",
            json: payload,
            message: 'Updated Page.'
          )
        end
      end

      class PagesShareEnable < PagesBase
        desc 'Enable an external share link for a Page'
        argument :page_id, required: true, desc: 'Page UUID'
        option :rotate, type: :boolean, default: false, desc: 'Rotate an existing share link'

        def call(page_id:, rotate: false, **)
          pages_request(
            method: :post,
            path: query_path("/api/pages/#{page_id(page_id)}/share", { rotate: rotate || nil }),
            message: 'Enabled the external share link.'
          )
        end
      end

      class PagesShareRevoke < PagesBase
        desc 'Revoke an external share link for a Page'
        argument :page_id, required: true, desc: 'Page UUID'

        def call(page_id:, **)
          pages_request(
            method: :delete,
            path: "/api/pages/#{page_id(page_id)}/share",
            message: 'Revoked the external share link.'
          )
        end
      end

      class PagesAssetUpload < PagesBase
        MAX_ASSET_BYTES = 50 * 1024 * 1024
        MIME_TYPES = {
          '.png' => 'image/png',
          '.jpg' => 'image/jpeg',
          '.jpeg' => 'image/jpeg',
          '.gif' => 'image/gif',
          '.svg' => 'image/svg+xml',
          '.webp' => 'image/webp',
          '.ico' => 'image/x-icon',
          '.bmp' => 'image/bmp'
        }.freeze

        desc 'Upload an image asset to Pages'
        argument :file, required: true, desc: 'PNG, JPG, GIF, SVG, WebP, ICO, or BMP file'

        def call(file:, **)
          path = required_file(file, 'file')
          if File.size(path) > MAX_ASSET_BYTES
            raise Error.new(code: 'invalid_input', message: 'Asset file exceeds the 50 MB limit.')
          end

          content_type = MIME_TYPES[File.extname(path).downcase]
          raise Error.new(code: 'invalid_input', message: 'Asset file type is not supported.') if content_type.nil?

          boundary = "----feedmob#{SecureRandom.hex(16)}"
          body = multipart_body(boundary, path, content_type)
          pages_request(
            method: :post,
            path: '/api/assets/upload',
            body:,
            headers: { 'Content-Type' => "multipart/form-data; boundary=#{boundary}" },
            message: 'Uploaded Pages asset.'
          )
        end

        private

        def multipart_body(boundary, path, content_type)
          filename = File.basename(path).gsub(/[\\"]/) { |character| "\\#{character}" }
          body = "--#{boundary}\r\n"
          body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n"
          body << "Content-Type: #{content_type}\r\n\r\n"
          body << File.binread(path)
          body << "\r\n--#{boundary}--\r\n"
          body.force_encoding(Encoding::BINARY)
        end
      end
    end
  end
end
