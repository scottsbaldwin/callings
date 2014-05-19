require 'sinatra'
require 'redis'
require './app'
require './middlewares/realtime_backend'

use Callings::RealtimeBackend
run Callings::App
