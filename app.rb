require 'sinatra/base'
require 'securerandom'

module Callings
  class App < Sinatra::Base

    use Rack::Auth::Basic, "Protected Area" do |username, password|
      ENV['AUTH_USER'] && ENV['AUTH_PASS'] &&
      username == ENV['AUTH_USER'] &&
      password == ENV['AUTH_PASS']
    end

    get "/assets/js/application.js" do
      content_type :js
      @uuid = request.params['name'] || SecureRandom.uuid
      @scheme = ENV['RACK_ENV'] == "production" ? "wss://" : "ws://"
      erb :"application.js"
    end

    get "/" do
      erb :"index.html"
    end

  end
end
