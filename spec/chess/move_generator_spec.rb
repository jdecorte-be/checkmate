require 'spec_helper'

RSpec.describe Chess::MoveGenerator do
  def board_for(fen)
    Chess::Board.from_fen(fen)
  end

  it 'generates knight moves that jump over other pieces' do
    board = board_for('8/8/8/8/3N4/8/8/8 w - - 0 1')
    dests = described_class.legal_moves(board, 'd4').map(&:to).sort
    expect(dests).to eq(%w[b3 b5 c2 c6 e2 e6 f3 f5].sort)
  end

  it 'stops a sliding piece at the first blocker and allows the capture' do
    board = board_for('8/8/8/8/3R4/3p4/8/8 w - - 0 1')
    dests = described_class.legal_moves(board, 'd4').select { |m| m.to.start_with?('d') }.map(&:to)
    expect(dests).to include('d3')
    expect(dests).not_to include('d2')
  end

  it 'allows a two-square pawn push only from the start rank' do
    board = board_for('8/8/8/8/8/4P3/8/8 w - - 0 1')
    dests = described_class.legal_moves(board, 'e3').map(&:to)
    expect(dests).to eq(%w[e4])
  end

  it 'generates en passant captures' do
    board = board_for('8/8/8/3pP3/8/8/8/8 w - d6 0 1')
    dests = described_class.legal_moves(board, 'e5').map(&:to)
    expect(dests).to include('d6')
  end

  it 'generates all four promotion choices at the last rank' do
    board = board_for('8/4P3/8/8/8/8/8/8 w - - 0 1')
    promos = described_class.legal_moves(board, 'e7').map(&:promotion).sort
    expect(promos).to eq(%w[b n q r])
  end

  it 'forbids a pinned piece from moving off the pin line' do
    board = board_for('4r3/8/8/8/4R3/8/8/4K3 w - - 0 1')
    dests = described_class.legal_moves(board, 'e4').map(&:to).sort
    expect(dests).to eq(%w[e2 e3 e5 e6 e7 e8].sort)
  end

  it 'castles kingside when the path is clear and safe' do
    board = board_for('8/8/8/8/8/8/8/4K2R w K - 0 1')
    dests = described_class.legal_moves(board, 'e1').map(&:to)
    expect(dests).to include('g1')
  end

  it 'forbids castling through an attacked square' do
    board = board_for('8/8/8/8/8/5r2/8/4K2R w K - 0 1')
    dests = described_class.legal_moves(board, 'e1').map(&:to)
    expect(dests).not_to include('g1')
  end

  it "returns no moves for the side that isn't on move" do
    board = board_for(Chess::Game::STARTING_FEN)
    expect(described_class.legal_moves(board, 'e7')).to eq([])
  end

  it 'castles queenside when the path is clear and safe' do
    board = board_for('8/8/8/8/8/8/8/R3K3 w Q - 0 1')
    dests = described_class.legal_moves(board, 'e1').map(&:to)
    expect(dests).to include('c1')
  end

  it 'forbids queenside castling when a square between king and rook is occupied' do
    board = board_for('8/8/8/8/8/8/8/R2NK3 w Q - 0 1')
    dests = described_class.legal_moves(board, 'e1').map(&:to)
    expect(dests).not_to include('c1')
  end

  it 'forbids castling while the king is currently in check' do
    board = board_for('4r3/8/8/8/8/8/8/4K2R w K - 0 1')
    dests = described_class.legal_moves(board, 'e1').map(&:to)
    expect(dests).not_to include('g1')
  end

  it 'only allows en passant immediately after the double push, not on a later turn' do
    game = Chess::Game.new('8/8/8/3pP3/8/8/8/4K2k w - d6 0 1')
    game.move('e1', 'd1') # white declines the en passant capture
    game.move('h1', 'g1') # black makes any move; the en passant window closes
    dests = described_class.legal_moves(game.board, 'e5').map(&:to)
    expect(dests).not_to include('d6')
  end

  it 'generates promotion choices for a capturing pawn move too' do
    board = board_for('3n4/4P3/8/8/8/8/8/8 w - - 0 1')
    promos = described_class.legal_moves(board, 'e7').select { |m| m.to == 'd8' }.map(&:promotion).sort
    expect(promos).to eq(%w[b n q r])
  end
end
