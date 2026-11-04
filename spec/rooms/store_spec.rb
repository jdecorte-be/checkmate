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

  describe 'room codes' do
    it 'never uses the easily-confused characters 0, O, 1 or I' do
      codes = Array.new(300) { store.create.code }.join
      expect(codes).not_to match(/[0O1I]/)
    end

    it 'draws from an alphabet of exactly 32 characters' do
      expect(Rooms::Room::CODE_CHARS.length).to eq(32)
      expect(Rooms::Room::CODE_CHARS.uniq.length).to eq(32)
    end
  end

  describe 'stale room sweeping' do
    it 'drops rooms older than 12 hours the next time a room is created' do
      old = store.create
      fresh = store.create
      old.instance_variable_set(:@created_at, Time.now - described_class::MAX_AGE - 1)

      store.create
      expect(store.find(old.code)).to be_nil
      expect(store.find(fresh.code)).to eq(fresh)
    end

    it 'keeps a room that is just under the 12 hour cutoff' do
      room = store.create
      room.instance_variable_set(:@created_at, Time.now - described_class::MAX_AGE + 60)
      store.create
      expect(store.find(room.code)).to eq(room)
    end
  end

  describe '#find' do
    it 'returns nil for a nil code instead of raising' do
      expect(store.find(nil)).to be_nil
    end
  end

  describe '#join' do
    it 'accepts a lowercase code' do
      room = store.create
      joined, token = store.join(room.code.downcase)
      expect(joined).to eq(room)
      expect(token).to match(/\A\h{32}\z/)
    end

    it 'gives black a different token than white' do
      room = store.create
      _, token = store.join(room.code)
      expect(token).not_to eq(room.white_token)
    end
  end

  describe '#apply_move' do
    it 'clamps the mover\'s clock at zero rather than going negative' do
      room = store.create
      store.join(room.code)
      room.turn_started_at = Time.now - (Rooms::Room::TIME_LIMIT_MS / 1000.0) - 30
      store.apply_move(room, 'fen', {}, 'white', game_over: false)
      expect(room.clock['white']).to eq(0)
    end

    it 'does not touch either clock when the game clock has not started' do
      room = store.create
      store.apply_move(room, 'fen', {}, 'white', game_over: false)
      expect(room.clock).to eq('white' => Rooms::Room::TIME_LIMIT_MS, 'black' => Rooms::Room::TIME_LIMIT_MS)
    end

    it 'restarts the turn timer for the next player after a non-final move' do
      room = store.create
      store.join(room.code)
      room.turn_started_at = Time.now - 10
      store.apply_move(room, 'fen', {}, 'white', game_over: false)
      expect(room.turn_started_at).to be_within(1).of(Time.now)
    end

    it 'stamps each recorded move with the room version' do
      room = store.create
      store.join(room.code)
      store.apply_move(room, 'fen1', { lastMove: 'a' }, 'white', game_over: false)
      store.apply_move(room, 'fen2', { lastMove: 'b' }, 'black', game_over: false)
      expect(room.version).to eq(2)
      expect(room.last_move).to eq(lastMove: 'b', version: 2)
    end
  end

  describe '#check_timeout!' do
    it 'declares white the winner when black runs out' do
      room = store.create
      store.join(room.code)
      room.turn_started_at = Time.now - (Rooms::Room::TIME_LIMIT_MS / 1000.0) - 1
      expect(store.check_timeout!(room, 'black')).to eq('winner' => 'white', 'reason' => 'timeout')
      expect(room.clock['black']).to eq(0)
      expect(room.turn_started_at).to be_nil
    end

    it 'only charges the side to move, not the waiting side' do
      room = store.create
      store.join(room.code)
      room.clock['black'] = 1
      room.turn_started_at = Time.now - 5
      expect(store.check_timeout!(room, 'white')).to be_nil
      expect(room.result).to be_nil
    end
  end
end

RSpec.describe Rooms::Room do
  subject(:room) { described_class.new('ABCDE') }

  let(:now) { Time.at(1_000_000) }

  describe '#remaining_ms' do
    it 'returns the stored time for the color that is not on move' do
      room.turn_started_at = now - 5
      expect(room.remaining_ms('black', 'white', now: now)).to eq(described_class::TIME_LIMIT_MS)
    end

    it 'subtracts the running turn time for the color on move, to the millisecond' do
      room.turn_started_at = now - 2.5
      expect(room.remaining_ms('white', 'white', now: now)).to eq(described_class::TIME_LIMIT_MS - 2500)
    end

    it 'never goes below zero' do
      room.turn_started_at = now - 100_000
      expect(room.remaining_ms('white', 'white', now: now)).to eq(0)
    end

    it 'freezes the clock once there is a result' do
      room.turn_started_at = now - 30
      room.result = { 'winner' => 'black', 'reason' => 'timeout' }
      expect(room.remaining_ms('white', 'white', now: now)).to eq(described_class::TIME_LIMIT_MS)
    end

    it 'does not run before the clock is started' do
      expect(room.remaining_ms('white', 'white', now: now)).to eq(described_class::TIME_LIMIT_MS)
    end
  end

  describe '#color_for' do
    it 'maps tokens to colors and rejects nil or unknown tokens' do
      room.black_token = 'b' * 32
      expect(room.color_for(room.white_token)).to eq('white')
      expect(room.color_for('b' * 32)).to eq('black')
      expect(room.color_for('nope')).to be_nil
      expect(room.color_for(nil)).to be_nil
    end

    it 'does not match a nil token to an empty black seat' do
      expect(room.black_token).to be_nil
      expect(room.color_for(nil)).to be_nil
    end
  end
end
