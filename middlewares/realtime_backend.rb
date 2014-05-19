require 'redis'
require 'faye/websocket'
require 'json'
require 'uri'

module Callings
  class RealtimeBackend
    KEEPALIVE_TIME = 15 # in seconds

    def initialize(app)
      @app     = app
      @clients = []

      uri = URI.parse(ENV["REDISCLOUD_URL"])
      $redis = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
    end

    def call(env)
      if Faye::WebSocket.websocket?(env)
        ws = Faye::WebSocket.new(env, nil, { ping: KEEPALIVE_TIME })
        ws.on :open do |event|
          @clients << ws
          # get the data from redis and send it to new connection
          callings = get_callings_data
          ws.send(create_message('join', callings))
        end

        ws.on :message do |event|
          message = JSON.parse(event.data)
          if message['topic'] == 'move'
            payload  = message['payload']
            id       = payload['id']
            from     = payload['from']
            new_list = destination(from, payload['direction'])

            callings = get_callings_data
            topic    = 'nochange'
            if new_list
              calling  = callings[from][id]
              calling['status'] = new_list
              callings[new_list] = {} unless callings[new_list]
              callings[new_list][id] = calling
              callings[from].delete(id)
              store_callings_data(callings)
              topic = 'moved'
            end

            broadcast(create_message(topic, callings))
          end

          if message['topic'] == 'delete'
            id = message['payload']
            callings = get_callings_data
            callings.each do |status, list|
              list.delete(id) if list.has_key?(id)
            end
            store_callings_data(callings)
            broadcast(create_message('deleted', callings))
          end

          if message['topic'] == 'save'
            payload = message['payload']
            payload['id'] = SecureRandom.uuid unless payload['id']

            # get everything from redis
            callings = get_callings_data

            # delete from any lists it appears in besides the new one
            callings.each do |status, list|
              list.delete(payload['id']) if list.has_key?(payload['id'])
            end

            # store the payload
            callings[payload['status']] = {} unless callings[payload['status']]
            callings[payload['status']][payload['id']] = payload
            store_callings_data(callings)

            # broadcast everything to everyone
            broadcast(create_message('saved', callings))
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

    def get_callings_data
      json = $redis.get('callings-wip') || "{}"
      callings = JSON.parse(json) || {}
      callings
    end

    def store_callings_data(callings)
      json = callings.to_json
      $redis.set('callings-wip', json)
    end

    def destination(from, direction)
      lists = %w{extend announce set-apart record}
      index = lists.index from
      result = lists[index-1] if index > 0 && direction == 'left'
      result = lists[index+1] if index < lists.length - 1 && direction == 'right'
      result
    end

    def create_message(topic, message)
      JSON.generate({ topic: topic, payload: message })
    end

    def broadcast(message)
      @clients.each { |client| client.send(message) }
    end
  end
end
