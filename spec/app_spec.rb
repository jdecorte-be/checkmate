require 'spec_helper'
require 'json'

RSpec.describe App do
  it 'serves the frontend' do
    get '/'
    expect(last_response).to be_ok
    expect(last_response.body).to include('board')
  end

  it 'returns the starting position' do
    get '/api/game'
    body = JSON.parse(last_response.body)
    expect(body['fen']).to eq(Chess::Game::STARTING_FEN)
    expect(body['turn']).to eq('white')
    expect(body['checkmate']).to eq(false)
  end

  it 'lists legal moves for the side to move only' do
    get '/api/legal_moves'
    body = JSON.parse(last_response.body)
    expect(body['e2']).to contain_exactly('e3', 'e4')
    expect(body).not_to have_key('e7')
  end

  it 'applies a move, returns the updated fen, and flips the turn' do
    post '/api/move', { from: 'e2', to: 'e4' }.to_json, 'CONTENT_TYPE' => 'application/json'
    body = JSON.parse(last_response.body)
    expect(last_response).to be_ok
    expect(body['fen']).to start_with('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR')
    expect(body['lastMove']).to eq('from' => 'e2', 'to' => 'e4')
    expect(body['turn']).to eq('black')
  end

  it 'rejects a move from an empty square' do
    post '/api/move', { from: 'e4', to: 'e5' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eq(422)
  end

  it 'rejects an illegal move from an occupied square' do
    post '/api/move', { from: 'e2', to: 'e5' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eq(422)
  end

  it "rejects moving the side that isn't on move" do
    post '/api/move', { from: 'e7', to: 'e5' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eq(422)
  end

  it 'reports the ai difficulty tiers and current elo' do
    get '/api/difficulty'
    body = JSON.parse(last_response.body)
    expect(body['levels']).to eq(Ai::Engine.levels)
    expect(body['elo']).to eq(1200)
  end

  it 'updates the ai difficulty, snapping to the nearest tier' do
    post '/api/difficulty', { elo: 50 }.to_json, 'CONTENT_TYPE' => 'application/json'
    body = JSON.parse(last_response.body)
    expect(body['elo']).to eq(400)

    get '/api/difficulty'
    expect(JSON.parse(last_response.body)['elo']).to eq(400)
  end

  it 'plays a legal ai move for whichever side is to move' do
    post '/api/ai_move'
    expect(last_response).to be_ok
    body = JSON.parse(last_response.body)
    expect(body['turn']).to eq('black')
    expect(body['lastMove']['from']).not_to be_nil
  end

  def play_fools_mate
    post '/api/move', { from: 'f2', to: 'f3' }.to_json, 'CONTENT_TYPE' => 'application/json'
    post '/api/move', { from: 'e7', to: 'e5' }.to_json, 'CONTENT_TYPE' => 'application/json'
    post '/api/move', { from: 'g2', to: 'g4' }.to_json, 'CONTENT_TYPE' => 'application/json'
    post '/api/move', { from: 'd8', to: 'h4' }.to_json, 'CONTENT_TYPE' => 'application/json'
  end

  it 'reports checkmate via the move endpoint and then rejects further moves' do
    play_fools_mate
    expect(JSON.parse(last_response.body)['checkmate']).to be true

    post '/api/move', { from: 'h1', to: 'g1' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eq(422)
  end

  it 'rejects an ai move request once the game is over' do
    play_fools_mate
    post '/api/ai_move'
    expect(last_response.status).to eq(422)
  end

  describe '1v1 rooms' do
    def new_client
      Rack::Test::Session.new(Rack::MockSession.new(App))
    end

    it 'lets the creator share a 5-character code that a friend can join' do
      post '/api/rooms'
      body = JSON.parse(last_response.body)
      expect(body['code']).to match(/\A[A-Z0-9]{5}\z/)
      expect(body['color']).to eq('white')
      expect(body['status']).to eq('waiting')

      friend = new_client
      friend.post '/api/rooms/join', { code: body['code'] }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(friend.last_response).to be_ok
      join_body = JSON.parse(friend.last_response.body)
      expect(join_body['color']).to eq('black')
      expect(join_body['status']).to eq('active')
    end

    it 'returns 404 when joining a code that does not exist' do
      post '/api/rooms/join', { code: 'ZZZZZ' }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq(404)
    end

    it 'returns 409 when a room already has two players' do
      post '/api/rooms'
      code = JSON.parse(last_response.body)['code']

      new_client.post '/api/rooms/join', { code: code }.to_json, 'CONTENT_TYPE' => 'application/json'
      second_client = new_client
      second_client.post '/api/rooms/join', { code: code }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(second_client.last_response.status).to eq(409)
    end

    it 'lets each player move only their own color, in turn' do
      post '/api/rooms'
      code = JSON.parse(last_response.body)['code']
      white = self

      black = new_client
      black.post '/api/rooms/join', { code: code }.to_json, 'CONTENT_TYPE' => 'application/json'

      black.post "/api/rooms/#{code}/move", { from: 'e2', to: 'e4' }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(black.last_response.status).to eq(403)

      white.post "/api/rooms/#{code}/move", { from: 'e2', to: 'e4' }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(white.last_response).to be_ok
      body = JSON.parse(white.last_response.body)
      expect(body['turn']).to eq('black')
      expect(body['version']).to eq(1)

      white.post "/api/rooms/#{code}/move", { from: 'e7', to: 'e5' }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(white.last_response.status).to eq(403)

      black.post "/api/rooms/#{code}/move", { from: 'e7', to: 'e5' }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(black.last_response).to be_ok

      black.get "/api/rooms/#{code}"
      poll_body = JSON.parse(black.last_response.body)
      expect(poll_body['version']).to eq(2)
      expect(poll_body['move']['lastMove']).to eq('from' => 'e7', 'to' => 'e5')
    end

    it 'rejects a move from someone who is not in the room' do
      post '/api/rooms'
      code = JSON.parse(last_response.body)['code']

      bystander = new_client
      bystander.post "/api/rooms/#{code}/move", { from: 'e2', to: 'e4' }.to_json,
                      'CONTENT_TYPE' => 'application/json'
      expect(bystander.last_response.status).to eq(403)
    end

    it 'gives each side a 10-minute clock once the game starts' do
      post '/api/rooms'
      code = JSON.parse(last_response.body)['code']

      black = new_client
      black.post '/api/rooms/join', { code: code }.to_json, 'CONTENT_TYPE' => 'application/json'
      body = JSON.parse(black.last_response.body)
      expect(body['clocks']['white']).to be_within(1000).of(10 * 60 * 1000)
      expect(body['clocks']['black']).to be_within(1000).of(10 * 60 * 1000)
    end

    it "declares the opponent the winner when a player's clock runs out" do
      post '/api/rooms'
      code = JSON.parse(last_response.body)['code']
      white = self

      black = new_client
      black.post '/api/rooms/join', { code: code }.to_json, 'CONTENT_TYPE' => 'application/json'

      room = App::ROOMS.find(code)
      room.turn_started_at = Time.now - (Rooms::Room::TIME_LIMIT_MS / 1000.0) - 1

      white.post "/api/rooms/#{code}/move", { from: 'e2', to: 'e4' }.to_json, 'CONTENT_TYPE' => 'application/json'
      expect(white.last_response.status).to eq(409)
      body = JSON.parse(white.last_response.body)
      expect(body['result']).to eq('winner' => 'black', 'reason' => 'timeout')

      black.get "/api/rooms/#{code}"
      poll_body = JSON.parse(black.last_response.body)
      expect(poll_body['result']).to eq('winner' => 'black', 'reason' => 'timeout')
    end
  end
end
