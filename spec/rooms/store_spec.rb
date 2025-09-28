require 'spec_helper'
require_relative '../../lib/rooms/store'

RSpec.describe Rooms::Store do
  subject(:store) { described_class.new }

  describe '#create' do
    it 'generates a 5-character code and assigns the creator as white' do
      room = store.create
      expect(room.code).to match(/\A[A-Z0-9]{5}\z/)
      expect(room.white_token).not_to be_nil
      expect(room.black_token).to be_nil
      expect(room.status).to eq('waiting')
      expect(room.fen).to eq(Chess::Game::STARTING_FEN)
    end

    it 'never hands out the same code twice' do
      codes = Array.new(100) { store.create.code }
      expect(codes.uniq.length).to eq(codes.length)
    end
  end

  describe '#find' do
    it 'looks codes up case-insensitively' do
      room = store.create
      expect(store.find(room.code.downcase)).to eq(room)
    end

    it 'returns nil for an unknown code' do
      expect(store.find('ZZZZZ')).to be_nil
    end
  end

  describe '#join' do
    it 'assigns the joining player as black and marks the room active' do
      room = store.create
      joined_room, token = store.join(room.code)
      expect(joined_room).to eq(room)
      expect(token).not_to be_nil
      expect(room.black_token).to eq(token)
      expect(room.status).to eq('active')
    end

    it 'refuses to double-join a full room' do
      room = store.create
      store.join(room.code)
      _, token = store.join(room.code)
      expect(token).to be_nil
    end

    it 'returns nil for an unknown code' do
      room, token = store.join('ZZZZZ')
      expect(room).to be_nil
      expect(token).to be_nil
    end

    it "starts the game's clock" do
      room = store.create
      expect(room.turn_started_at).to be_nil
      store.join(room.code)
      expect(room.turn_started_at).not_to be_nil
    end
  end

  describe '#apply_move' do
    it 'records the new fen and bumps the version on every move' do
      room = store.create
      store.join(room.code)
      store.apply_move(room, 'fen-after-move', { fen: 'fen-after-move' }, 'white', game_over: false)
      expect(room.fen).to eq('fen-after-move')
      expect(room.version).to eq(1)
      expect(room.last_move).to eq(fen: 'fen-after-move', version: 1)
    end

    it "deducts the time the mover took to move from that color's clock" do
      room = store.create
      store.join(room.code)
      room.turn_started_at = Time.now - 5 # simulate 5 seconds of thinking time
      store.apply_move(room, 'fen-after-move', {}, 'white', game_over: false)
      expect(room.clock['white']).to be_within(200).of(Rooms::Room::TIME_LIMIT_MS - 5000)
      expect(room.clock['black']).to eq(Rooms::Room::TIME_LIMIT_MS)
    end

    it "stops the clock once the move ends the game" do
      room = store.create
      store.join(room.code)
      store.apply_move(room, 'fen-after-move', {}, 'white', game_over: true)
      expect(room.turn_started_at).to be_nil
    end
  end

  describe '#check_timeout!' do
    it 'returns nil while time remains' do
      room = store.create
      store.join(room.code)
      expect(store.check_timeout!(room, 'white')).to be_nil
    end

    it 'declares the other color the winner once a clock hits zero' do
      room = store.create
      store.join(room.code)
      room.turn_started_at = Time.now - (Rooms::Room::TIME_LIMIT_MS / 1000.0) - 1

      result = store.check_timeout!(room, 'white')
      expect(result).to eq('winner' => 'black', 'reason' => 'timeout')
      expect(room.result).to eq(result)
      expect(room.clock['white']).to eq(0)
    end

    it 'does not run the clock before both players have joined' do
      room = store.create
      room.instance_variable_set(:@turn_started_at, Time.now - 1_000_000)
      expect(store.check_timeout!(room, 'white')).to be_nil
    end

    it 'keeps returning the same result once the game has timed out' do
      room = store.create
      store.join(room.code)
      room.turn_started_at = Time.now - (Rooms::Room::TIME_LIMIT_MS / 1000.0) - 1
      first = store.check_timeout!(room, 'white')
      expect(store.check_timeout!(room, 'white')).to eq(first)
    end
  end
end
