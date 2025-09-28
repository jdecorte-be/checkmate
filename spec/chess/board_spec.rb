require 'spec_helper'

RSpec.describe Chess::Board do
  it 'round-trips the starting FEN through parsing and serialization' do
    fen = Chess::Game::STARTING_FEN
    expect(described_class.from_fen(fen).to_fen).to eq(fen)
  end

  it 'detects check along a file' do
    board = described_class.from_fen('4k3/8/8/8/8/8/8/4R3 w - - 0 1')
    expect(board.in_check?('b')).to be true
    expect(board.in_check?('w')).to be false
  end

  it 'does not consider a square attacked through a blocking piece' do
    board = described_class.from_fen('4k3/8/8/8/4P3/8/8/4R3 w - - 0 1')
    expect(board.in_check?('b')).to be false
  end

  it 'does not consider a diagonal attack blocked by an intervening piece' do
    board = described_class.from_fen('7k/8/5P2/8/8/8/8/B6K w - - 0 1')
    expect(board.in_check?('b')).to be false
  end

  it 'round-trips a mid-game FEN with partial castling rights and an en passant target' do
    fen = 'r1bqkbnr/ppp1pppp/2n5/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3'
    expect(described_class.from_fen(fen).to_fen).to eq(fen)
  end

  it 'removes castling rights for a rook that moves and for one captured on its home square' do
    board = described_class.from_fen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1')
    after = board.apply(Chess::Move.new(from: 'a1', to: 'a8'))
    expect(after.castling).to eq('Kk')
  end

  it 'resets the halfmove clock on a capture or a pawn move, and increments it otherwise' do
    quiet = described_class.from_fen('4k3/8/8/8/8/1N6/8/4K3 w - - 5 10')
    after_quiet = quiet.apply(Chess::Move.new(from: 'b3', to: 'd4'))
    expect(after_quiet.halfmove).to eq(6)

    pawn = described_class.from_fen('4k3/8/8/8/8/4P3/8/4K3 w - - 5 10')
    after_pawn = pawn.apply(Chess::Move.new(from: 'e3', to: 'e4'))
    expect(after_pawn.halfmove).to eq(0)

    capture = described_class.from_fen('4k3/8/8/8/8/1p6/8/N3K3 w - - 5 10')
    after_capture = capture.apply(Chess::Move.new(from: 'a1', to: 'b3'))
    expect(after_capture.halfmove).to eq(0)
  end
end
