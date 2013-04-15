module Rack
  class StreamingProxy

    class Error < StandardError; end

    # :stopdoc:
    VERSION = '1.1.0'
    LIBPATH = ::File.expand_path(::File.dirname(__FILE__)) + ::File::SEPARATOR
    PATH = ::File.expand_path(::File.join(::File.dirname(__FILE__), "..", "..")) + ::File::SEPARATOR
    # :startdoc:

    # Returns the version string for the library.
    #
    def self.version
      VERSION
    end

    # Returns the library path for the module. If any arguments are given,
    # they will be joined to the end of the libray path using
    # <tt>File.join</tt>.
    #
    def self.libpath( *args )
      args.empty? ? LIBPATH : ::File.join(LIBPATH, args.flatten)
    end

    # Returns the lpath for the module. If any arguments are given,
    # they will be joined to the end of the path using
    # <tt>File.join</tt>.
    #
    def self.path( *args )
      args.empty? ? PATH : ::File.join(PATH, args.flatten)
    end

    # Utility method used to require all files ending in .rb that lie in the
    # directory below this file that has the same name as the filename passed
    # in. Optionally, a specific _directory_ name can be passed in such that
    # the _filename_ does not have to be equivalent to the directory.
    #
    def self.require_all_libs_relative_to( fname, dir = nil )
      dir ||= ::File.basename(fname, '.*')
      search_me = ::File.expand_path(
        ::File.join(::File.dirname(fname), dir, '**', '*.rb'))

        Dir.glob(search_me).sort.each {|rb| require rb}
    end

    # Class instance variable for the logger.
    # Note that all instances of the Rack::StreamingProxy class will share this logger.
    class << self
      attr_accessor :logger
    end

    # The block provided to the initializer is given a Rack::Request
    # and should return:
    #
    #   * nil/false to skip the proxy and continue down the stack
    #   * a complete uri (with query string if applicable) to proxy to
    #
    # E.g.
    #
    #   use Rack::StreamingProxy do |req|
    #     if req.path.start_with?("/search")
    #       "http://some_other_service/search?#{req.query}"
    #     end
    #   end
    #
    # Most headers, request body, and HTTP method are preserved.
    #
    def initialize(app, &block)
      @request_uri = block
      @app = app
    end

    def call(env)
      req = Rack::Request.new(env)
      unless uri = request_uri.call(req)
        code, headers, body = app.call(env)
        unless headers['X-Accel-Redirect']
          return [code, headers, body]
        else
          proxy_env = env.merge("PATH_INFO" => headers['X-Accel-Redirect'])
          unless uri = request_uri.call(Rack::Request.new(proxy_env))
            raise "Could not proxy #{headers['X-Accel-Redirect']}: Path does not map to any uri"
          end
        end
      end
      begin # only want to catch proxy errors, not app errors
        proxy = ProxyRequest.new(req, uri, self.class.logger)
        [proxy.status, proxy.headers, proxy]
      rescue => e
        msg = "Proxy error when proxying to #{uri}: #{e.class}: #{e.message}"
        env["rack.errors"].puts msg
        env["rack.errors"].puts e.backtrace.map { |l| "\t" + l }
        env["rack.errors"].flush
        raise Error, msg
      end
    end

    protected

    attr_reader :request_uri, :app

  end

end

require "rack"
require "servolux"
require "net/https"
require "uri"
require "rack/streaming_proxy/railtie" if defined? ::Rails::Railtie
require "rack/streaming_proxy/proxy_request"
require "rack/streaming_proxy/piper"
