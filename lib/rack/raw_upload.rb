require 'mongo'
require 'rack/rewindable_input'
module Rack
  class RawUpload

    VERSION = '0.1.1'

    def initialize(app, opts = {})
      @app = app
      @paths = opts[:paths]
      @explicit = opts[:explicit]
      @tmpdir = opts[:tmpdir] || Dir::tmpdir      
      @paths = [@paths] if @paths.kind_of?(String)
      @db = Mongo::Connection.new.db(opts[:db])
      @grid = Mongo::Grid.new(@db)
    end

    def call(env)
      kick_in?(env) ? convert_and_pass_on(env) : @app.call(env)
    end

    def upload_path?(request_path)
      return true if @paths.nil?

      @paths.any? do |candidate|
        literal_path_match?(request_path, candidate) || wildcard_path_match?(request_path, candidate)
      end
    end

    private

    def convert_and_pass_on(env)
      env['rack.input'] = Rack::RewindableInput.new(env['rack.input']) unless env['rack.input'].is_a? Rack::RewindableInput 
      id  = @grid.put(env['rack.input'], :filename => env['HTTP_X_FILE_NAME'])
      env['rack.request.form_input'] = env['rack.input']
      env['rack.request.form_hash'] ||= {}
      env['rack.request.query_hash'] ||= {}
      env['rack.request.form_hash']['track'] ||= {}
      env['rack.request.query_hash']['track'] ||= {}
      env['rack.request.form_hash']['track']['file_id'] = id
      env['rack.request.query_hash']['track']['file_id'] = id
      env['rack.request.form_hash']['track']['file_name'] = env['HTTP_X_FILE_NAME']
      env['rack.request.query_hash']['track']['file_name'] = env['HTTP_X_FILE_NAME']
      size = env['rack.input'].instance_variable_get(:@rewindable_io).size
      env['rack.request.form_hash']['track']['file_size'] = size
      env['rack.request.query_hash']['track']['file_size'] = size
      env['rack.request.form_hash']['track']['file_type'] = env['CONTENT_TYPE']
      env['rack.request.query_hash']['track']['file_type'] = env['CONTENT_TYPE']
      if query_params = env['HTTP_X_QUERY_PARAMS']
        require 'json'
        params = JSON.parse(query_params)
        env['rack.request.form_hash'].merge!(params)
        env['rack.request.query_hash'].merge!(params)
      end
      @app.call(env)
    end

    def kick_in?(env)
      env['HTTP_X_FILE_UPLOAD'] == 'true' ||
        ! @explicit && env['HTTP_X_FILE_UPLOAD'] != 'false' && raw_file_post?(env) ||
        env.has_key?('HTTP_X_FILE_UPLOAD') && env['HTTP_X_FILE_UPLOAD'] != 'false' && raw_file_post?(env)
    end

    def raw_file_post?(env)
      upload_path?(env['PATH_INFO']) &&
        env['REQUEST_METHOD'] == 'POST' &&
        content_type_of_raw_file?(env['CONTENT_TYPE'])
    end

    def literal_path_match?(request_path, candidate)
      candidate == request_path
    end

    def wildcard_path_match?(request_path, candidate)
      return false unless candidate.include?('*')
      regexp = '^' + Regexp.escape(candidate.gsub("*", ""))
      !! (Regexp.new(regexp) =~ request_path)
    end
    
    def content_type_of_raw_file?(content_type)
      ! %w{application/x-www-form-urlencoded multipart/form-data}.include?(content_type)
    end
  end
end
