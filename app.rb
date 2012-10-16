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

      #raise Goliath::Validation::NotImplementedError.new("no downloader yet") unless downloader_connected?
    end

    if env['PATH_INFO'] == '/download'
      env[:download_stream] = true
    end
    env.logger.info headers
    env['async-headers'] = headers
  end

  def on_body(env, data)
    env['rack.input'] = nil
    unless env[:boundary_end]
      unless env['QUERY_STRING'] =~ /transfer_id=([0-9]+)/
        raise Goliath::Validation::VerificationError.new('no file given')
      end
      env[:transfer_id] = $1.to_i


      upload = @uploads[env[:transfer_id]]
      upload['status'] = 'uploading'
      upload['bytes_total'] = env['async-headers']['Content-Length']
      upload['bytes_uploaded'] ||= 0


      unless env['CONTENT_TYPE'] =~ MULTIPART
        raise Goliath::Validation::VerificationError.new('no file given')
      end

      boundary = $1
      boundary_start = "--#{boundary}"
      boundary_end = /#{EOL}--#{Regexp.quote(boundary)}--/n

      head_end = data.index(EOL+EOL)

      env.logger.info 'Upload size: ' + head_end.to_s
      head = data.slice!(0, head_end + 4)
      env.logger.info head

      env[:boundary_end] = boundary_end
    end

    if match_data = data.match(env[:boundary_end])

      boundary_end = data.index(match_data[0])
      data.slice!(boundary_end, data.size)

      @uploads[env[:transfer_id]]['status'] = 'finished'

      @uploads[env[:transfer_id]]['bytes_uploaded'] += data.length
      @connections[env[:transfer_id]].stream_send(data)

      transfer_id = env[:transfer_id]

      # closing downloader connection and cleaning up transfer data
      EM.add_timer(1) do
        @connections[transfer_id].stream_close
        @connections.delete(transfer_id)
        # Upload status data will be available next 30 seconds
        # assuming client will have enough time to sync
        EM.add_timer(30) do
          @uploads.delete(transfer_id)
        end
      end

      return
    end

    @uploads[env[:transfer_id]]['bytes_uploaded'] += data.length
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
    path_params = env['PATH_INFO'].split('/')
    case path_params[1]
      when nil
        then [200, {}, haml(:index)]
      when 'register_upload' then
        if params['filename']
          upload_id = get_request_id
          upload_data = {
              filename: params['filename'].split('\\').last,
              upload_id: upload_id,
              download_link: "http://#{env['HTTP_HOST']}/invite/#{upload_id}/#{params['filename'].split('\\').last}"
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
        transfer_id = path_params[2].to_i
        return [404, {}, '404'] unless @uploads.has_key?(transfer_id)

        upload = @uploads[transfer_id]
        upload['status'] = 'client.connected'

        @connections[transfer_id] = env

        [200, {'Content-disposition' => "attachment"}, Goliath::Response::STREAMING]
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


#runner = Goliath::Runner.new(ARGV, nil)
#runner.api = Stream.new
#runner.app = Goliath::Rack::Builder.build(Stream, runner.api)
#runner.run