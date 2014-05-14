require 'faye/websocket'
require 'json'

module Callings
  class RealtimeBackend
    KEEPALIVE_TIME = 15 # in seconds

    def initialize(app)
      @app     = app
      @clients = []
    end

    def call(env)
      if Faye::WebSocket.websocket?(env)
        ws = Faye::WebSocket.new(env, nil, { ping: KEEPALIVE_TIME })
        ws.on :open do |event|
          @clients << ws
        end

        ws.on :message do |event|
          message = JSON.parse(event.data)
          if (message['topic'] == 'SOME TOPIC')
            payload = message['payload']
            # do something with the payload
            broadcast(create_message('voted', payload))
          end
        end

        ws.on :close do |event|
          @clients.delete(ws)
          ws = nil
        end

        # Return async Rack response
        ws.rack_response
      else
        @app.call(env)
      end
    end

    private

    def create_message(topic, message)
      JSON.generate({ topic: topic, payload: message })
    end

    def broadcast(message)
      @clients.each { |client| client.send(message) }
    end
  end
end
