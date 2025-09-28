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
  end

  describe '#apply_move' do
    it 'records the new fen and bumps the version on every move' do
      room = store.create
      store.apply_move(room, 'fen-after-move', { fen: 'fen-after-move' })
      expect(room.fen).to eq('fen-after-move')
      expect(room.version).to eq(1)
      expect(room.last_move).to eq(fen: 'fen-after-move', version: 1)
    end
  end
end
