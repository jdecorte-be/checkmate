require 'spec_helper'

# Runs the full stack from config.ru (not just App) so we see the middleware order.
RSpec.describe 'config.ru' do
  let(:stack) { Rack::Builder.parse_file(File.expand_path('../config.ru', __dir__)) }
  let(:client) { Rack::Test::Session.new(Rack::MockSession.new(stack)) }

  %w[/pieces/cburnett/wK.svg /css/board.css /js/board.js /favicon.svg].each do |path|
    it "serves #{path} without touching the session cookie" do
      client.get path
      expect(client.last_response).to be_ok
      expect(client.last_response.headers['set-cookie']).to be_nil
    end
  end

  it 'still sets the session cookie for API requests' do
    client.get '/api/game'
    expect(client.last_response.headers['set-cookie']).to match(/rack\.session=/)
  end

  it 'keeps a joined 1v1 seat when an asset request that started earlier finishes later' do
    owner = Rack::Test::Session.new(Rack::MockSession.new(stack))
    owner.post '/api/rooms'
    code = JSON.parse(owner.last_response.body)['code']

    client.get '/api/game'
    stale_cookie = client.last_response.headers['set-cookie'][/rack\.session=[^;]+/]
    client.post '/api/rooms/join', { code: code }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(client.last_response).to be_ok

    # An image request sent with the pre-join cookie, answered after the join.
    client.get '/pieces/cburnett/bQ.svg', {}, 'HTTP_COOKIE' => stale_cookie
    client.get "/api/rooms/#{code}"
    expect(JSON.parse(client.last_response.body)['color']).to eq('black')
  end

  it 'still serves the index page through the app' do
    client.get '/'
    expect(client.last_response).to be_ok
    expect(client.last_response.body).to include('id="board"')
  end
end
