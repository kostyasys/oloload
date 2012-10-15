$: << File.dirname(__FILE__)

require "bundler"
Bundler.setup

require 'goliath'
require 'goliath/rack/templates'
require 'haml'
require "tilt"
require "json"

class Stream < Goliath::API
  EOL = "\r\n"
  MULTIPART_BOUNDARY = "AaB03x"
  MULTIPART = %r|\Amultipart/.*boundary=\"?([^\";,]+)\"?|n
  TOKEN = /[^\s()<>,;:\\"\/\[\]?=]+/
  CONDISP = /Content-Disposition:\s*#{TOKEN}\s*/i
  DISPPARM = /;\s*(#{TOKEN})=("(?:\\"|[^"])*"|#{TOKEN})*/
  RFC2183 = /^#{CONDISP}(#{DISPPARM})+$/i
  BROKEN_QUOTED = /^#{CONDISP}.*;\sfilename="(.*?)"(?:\s*$|\s*;\s*#{TOKEN}=)/i
  BROKEN_UNQUOTED = /^#{CONDISP}.*;\sfilename=(#{TOKEN})/i
  MULTIPART_CONTENT_TYPE = /Content-Type: (.*)#{EOL}/ni
  MULTIPART_CONTENT_DISPOSITION = /Content-Disposition:.*\s+name="?([^\";]*)"?/ni
  MULTIPART_CONTENT_ID = /Content-ID:\s*([^#{EOL}]*)/ni

  include Goliath::Rack::Templates
  use Goliath::Rack::Heartbeat
  use Goliath::Rack::Params

  use(Rack::Static,
        :root => Goliath::Application.app_path("public"),
        :urls => ["/favicon.ico", '/css', '/js', '/img'])

  def initialize
    @uploads = {}
    @connections = {}
  end


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
    env['rack.input'] = nil
    unless env[:boundary_end]
      unless env['QUERY_STRING'] =~ /transfer_id=([0-9]+)/
        raise Goliath::Validation::VerificationError.new('no file given')
      end
      env[:transfer_id] = $1.to_i
      env.logger.info 'transfer to ' + env[:transfer_id].to_s

      upload = @uploads[env[:transfer_id]]
      upload['status'] = 'uploading'



      unless env['CONTENT_TYPE'] =~ MULTIPART
        raise Goliath::Validation::VerificationError.new('no file given')
      end

      boundary = $1
      boundary_start = "--#{boundary}"
      boundary_end = /(?:#{EOL})?(--)#{Regexp.quote(boundary)}(--)/n

      head_end = data.index(EOL+EOL)
      head = data.slice(0, head_end + 4)
      env.logger.info head

      env[:boundary_end] = boundary_end

      data.slice!(0, head_end+4)
    end

    if match_data = data.match(env[:boundary_end])
      old_data = data.dup
      boundary_end = data.index(match_data[0])
      data.slice!(boundary_end, data.size)

      @uploads[env[:transfer_id]]['status'] = 'finished'
      @connections[env[:transfer_id]].stream_send(data)

      EM.add_timer(1) do
        @connections[env[:transfer_id]].stream_close
      end

      return
    end

    @connections[env[:transfer_id]].stream_send(data)
  end

  def on_close(env)
    if env[:transfer_id]
      env.logger.info 'closing: ' + env[:transfer_id]
      @uploads[env[:transfer_id]]['status'] = 'finished'
      @connections[env[:transfer_id]].stream_close
    end
  end


  def response(env)
    case env['PATH_INFO'].split('/')[1]
      when nil
        then [200, {}, haml(:index)]
      when 'register_upload' then
        if params['filename']
          upload_id = get_request_id
          upload_data = {
              filename: params['filename'].split('\\').last,
              upload_id: upload_id,
              download_link: "http://#{env['HTTP_HOST']}/invite/#{params['filename'].split('\\').last}?transfer_id=#{upload_id}"
          }
          @uploads[upload_id] = upload_data
          json_response(upload_data)
        else
          json_response()
        end

      when 'upload_status' then
        unless params['transfer_id'] || @uploads.has_key?(params['transfer_id'])
          json_response()
        end

        upload = @uploads[params['transfer_id'].to_i]
        json_response upload

      when 'invite' then
          return [404, {}, '404'] unless params['transfer_id'] || @uploads.has_key?(params['transfer_id'])

          upload = @uploads[params['transfer_id'].to_i]
          upload['status'] = 'client.connected'

          @connections[params['transfer_id'].to_i] = env

          [200, {'Content-disposition' => "attachment; filename='#{upload['filename']}'"}, Goliath::Response::STREAMING]
      else
        [200, {'Content-type' => 'text/plain'}, env['async-headers']]
    end
  end



  def json_response(data={})
    [200, {'Content-type' => 'application/json'}, data.to_json]
  end

  def get_request_id
    @id ||= 0
    @id+=1

    return @id
  end
end


runner = Goliath::Runner.new(ARGV, nil)
runner.api = Stream.new
runner.app = Goliath::Rack::Builder.build(Stream, runner.api)
runner.run