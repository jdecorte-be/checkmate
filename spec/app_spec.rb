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
end
