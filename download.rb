require "bundler"
Bundler.setup

require 'goliath'
require 'haml'

class CallbacksRegistry
  def self.get_downloader
    @@env
  end

  def self.register_downloader(down_stream)
    @@env = down_stream
  end
end

class Download < Goliath::API
  def response(env)
    CallbacksRegistry.register_downloader(env)
    [200, {}, Goliath::Response::STREAMING]
  end
end

class Stream < Goliath::API
  def on_headers(env, headers)
    env.logger.info 'received headers: ' + headers.inspect
    env['async-headers'] = headers
  end

  def on_body(env, data)
    env.logger.info 'received data: ' + data
    CallbacksRegistry.get_downloader.stream_send data
  end

  def on_close(env)
    CallbacksRegistry.get_downloader.stream_close
    env.logger.info 'closing connection'
  end

  def response(env)
    case env['PATH_INFO']
      when '/'

    end
    [200, {}, {body: 'ok', head: env['async-headers']}]
  end
end