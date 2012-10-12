$: << File.dirname(__FILE__)

require "bundler"
Bundler.setup

require 'goliath'
require 'goliath/rack/templates'
require 'haml'
require "tilt"

require "parser"

class Stream < Goliath::API

  def initialize
    @parsers = {}
  end

  def downloader_connected?
    !@downloader_env.nil?
  end

  def write_download_stream(data)
    @downloader_env.stream_send(data) if @downloader_env
  end

  def add_download_stream(down_stream)
    @downloader_env = down_stream
  end

  def close_download_stream
    return unless @downloader_env
    env.logger.info 'closing download stream'
    @downloader_env.stream_send 'closing connection'
    @downloader_env[:closed] = true
    @downloader_env.stream_close
    @downloader_env = nil
    'closed'
  end

  include Goliath::Rack::Templates

  def on_headers(env, headers)
    if env['REQUEST_METHOD'] == 'POST'
      env[:uploading] = true
      env.logger.info 'Upload size: ' + headers['Content-Length'].to_s

      #raise Goliath::Validation::NotImplementedError.new("no downloader yet") unless downloader_connected?
    end

    if env['PATH_INFO'] == '/download'
      env[:download_stream] = true
    end

    env['async-headers'] = headers
  end

  def on_body(env, data)
    #env[:request_id] ||= get_request_id
    #_id = env[:request_id]
    unless env[:boundary_end]
      unless env['CONTENT_TYPE'] =~ MULTIPART
        raise Goliath::Validation::VerificationError.new('no file given')
      end
      boundary = $1
      boundary_start = "--#{boundary}"
      boundary_end = /(?:#{EOL})?#{Regexp.quote(boundary)}(#{EOL}|--)/n

      head_end = data.index(EOL+EOL)
      head = data.slice(0, head_end + 4)
      env.logger.info head

      env[:boundary_end] = boundary_end

      data.slice!(0, head_end+4)
    end

    if data =~ env[:boundary_end]
      boundary_end = data.index($1)
      data.slice!(boundary_end, data.size)
    end

    #unless @parsers[_id]
    #
    #  parser = Parser.new
    #  @parsers[_id] = parser
    #  env.logger.info 'uploading'
    #  env.logger.info 'block size: ' + data.length.to_s
    #  parser.on :part_data do |buf, from, to|
    write_download_stream(data)
      #end
    #end
    #

  end

  def on_close(env)
    env.logger.info env[:uploading]
    close_download_stream if env[:uploading]
  end


  def response(env)
    case env['PATH_INFO']
      when '/'
        then [200, {}, haml(:index)]
      when '/download'
        then
            add_download_stream(env)
            [200, {}, Goliath::Response::STREAMING]
      else
        [200, {'Content-type' => 'text/plain'}, env['async-headers']]
    end
  end

  def get_request_id
    @id ||= 0
    @id+=1

    return @id
  end
end