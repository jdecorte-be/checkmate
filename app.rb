require 'sinatra/base'
require 'sinatra/json'
require 'json'
require 'securerandom'
require_relative 'lib/chess/game'
require_relative 'lib/ai/engine'

class App < Sinatra::Base
  set :public_folder, File.join(__dir__, 'public')
  enable :sessions
  set :session_secret, ENV.fetch('SESSION_SECRET') { SecureRandom.hex(32) }
  set :host_authorization, permitted_hosts: []

  DEFAULT_ELO = 1200

  get '/' do
    send_file File.join(settings.public_folder, 'index.html')
  end

  get '/api/game' do
    game = Chess::Game.new(current_fen)
    json({ fen: game.fen, turn: game.active_color }.merge(game.status))
  end

  get '/api/legal_moves' do
    json Chess::Game.new(current_fen).legal_moves
  end

  get '/api/difficulty' do
    json levels: Ai::Engine.levels, elo: current_elo
  end

  post '/api/difficulty' do
    payload = JSON.parse(request.body.read)
    session[:ai_elo] = Ai::Engine.new(elo: payload['elo'].to_i).elo
    json levels: Ai::Engine.levels, elo: session[:ai_elo]
  end

  post '/api/new_game' do
    session[:fen] = Chess::Game::STARTING_FEN
    game = Chess::Game.new(session[:fen])
    json({ fen: game.fen, turn: game.active_color }.merge(game.status))
  end

  post '/api/move' do
    payload = JSON.parse(request.body.read)
    game = Chess::Game.new(current_fen)
    result = game.move(payload['from'], payload['to'], promotion: payload['promotion'])
    session[:fen] = result[:fen]
    json move_response(game, result)
  rescue ArgumentError => e
    status 422
    json error: e.message
  end

  post '/api/ai_move' do
    game = Chess::Game.new(current_fen)
    engine = Ai::Engine.new(elo: current_elo)
    chosen = engine.choose_move(game, debug: truthy?(params['debug']))
    halt 422, json(error: 'no legal moves') unless chosen

    result = game.move(chosen[:from], chosen[:to], promotion: chosen[:promotion])
    session[:fen] = result[:fen]
    response = move_response(game, result)
    response[:aiDebug] = chosen[:debug] if chosen[:debug]
    json response
  end

  private

  def current_fen
    session[:fen] ||= Chess::Game::STARTING_FEN
  end

  def current_elo
    session[:ai_elo] ||= DEFAULT_ELO
  end

  def truthy?(value)
    %w[1 true].include?(value.to_s)
  end

  def move_response(game, result)
    {
      fen: result[:fen],
      turn: game.active_color,
      lastMove: result[:last_move],
      capture: result[:capture],
      secondary: result[:secondary],
      promotion: result[:promotion],
      check: result[:check],
      checkmate: result[:checkmate],
      stalemate: result[:stalemate]
    }
  end

  run! if app_file == $PROGRAM_NAME
end
