require 'spec_helper'

RSpec.describe Chess::Game do
  it 'parses the starting placement' do
    game = described_class.new
    expect(game.placement['e2']).to eq('P')
    expect(game.placement['e7']).to eq('p')
    expect(game.placement['e4']).to be_nil
  end

  it 'moves a piece and updates the fen' do
    game = described_class.new
    result = game.move('e2', 'e4')
    expect(result[:capture]).to be_nil
    expect(game.placement['e4']).to eq('P')
    expect(game.placement['e2']).to be_nil
  end

  it 'reports a capture' do
    game = described_class.new('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1')
    game.move('d7', 'd5')
    result = game.move('e4', 'd5')
    expect(result[:capture]).to eq('d5')
  end

  it 'raises when moving from an empty square' do
    game = described_class.new
    expect { game.move('e4', 'e5') }.to raise_error(ArgumentError)
  end

  it "raises when it isn't that color's turn" do
    game = described_class.new
    expect { game.move('e7', 'e5') }.to raise_error(ArgumentError)
  end

  it 'raises on a pseudo-legal-but-illegal move (knight moving like a bishop)' do
    game = described_class.new
    expect { game.move('b1', 'd3') }.to raise_error(ArgumentError)
  end

  it "rejects a move that would leave the mover's own king in check" do
    game = described_class.new('4r3/8/8/8/4R3/8/8/4K3 w - - 0 1')
    expect { game.move('e4', 'd4') }.to raise_error(ArgumentError)
  end

  it 'flips the active color, bumps the fullmove count after black moves, and tracks en passant targets' do
    game = described_class.new
    expect(game.active_color).to eq('white')

    game.move('e2', 'e4')
    expect(game.active_color).to eq('black')
    expect(game.fen).to end_with(' b KQkq e3 0 1')

    game.move('e7', 'e5')
    expect(game.active_color).to eq('white')
    expect(game.fen).to end_with(' w KQkq e6 0 2')
  end

  it 'performs en passant, clearing the captured pawn from its actual square' do
    game = described_class.new('8/8/8/3pP3/8/8/8/4K2k w - d6 0 1')
    result = game.move('e5', 'd6')
    expect(result[:capture]).to eq('d5')
    expect(game.placement['d5']).to be_nil
    expect(game.placement['d6']).to eq('P')
  end

  it 'promotes a pawn to a queen by default' do
    game = described_class.new('8/4P3/8/8/8/8/7k/4K3 w - - 0 1')
    result = game.move('e7', 'e8')
    expect(result[:promotion]).to eq('wQ')
    expect(game.placement['e8']).to eq('Q')
  end

  it 'underpromotes when requested' do
    game = described_class.new('8/4P3/8/8/8/8/7k/4K3 w - - 0 1')
    result = game.move('e7', 'e8', promotion: 'n')
    expect(result[:promotion]).to eq('wN')
    expect(game.placement['e8']).to eq('N')
  end

  it 'castles kingside, moving both the king and the rook' do
    game = described_class.new('8/8/8/8/8/8/8/4K2R w K - 0 1')
    result = game.move('e1', 'g1')
    expect(result[:secondary]).to eq(from: 'h1', to: 'f1')
    expect(game.placement['g1']).to eq('K')
    expect(game.placement['f1']).to eq('R')
  end

  it 'castles queenside, moving both the king and the rook' do
    game = described_class.new('8/8/8/8/8/8/8/R3K3 w Q - 0 1')
    result = game.move('e1', 'c1')
    expect(result[:secondary]).to eq(from: 'a1', to: 'd1')
    expect(game.placement['c1']).to eq('K')
    expect(game.placement['d1']).to eq('R')
  end

  it "can't capture your own piece" do
    game = described_class.new
    expect { game.move('a1', 'a2') }.to raise_error(ArgumentError)
  end

  it 'removes both sides\' relevant castling rights when a rook moves and captures the other rook' do
    game = described_class.new('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1')
    result = game.move('a1', 'a8')
    expect(result[:capture]).to eq('a8')
    expect(game.fen).to include(' b Kk ')
  end

  it 'detects checkmate (fool\'s mate)' do
    game = described_class.new
    game.move('f2', 'f3')
    game.move('e7', 'e5')
    game.move('g2', 'g4')
    result = game.move('d8', 'h4')
    expect(result[:checkmate]).to be true
    expect(result[:check]).to eq('e1')
  end

  it 'reports stalemate status without requiring a move' do
    game = described_class.new('k7/8/1Q6/8/8/8/8/6K1 b - - 0 1')
    expect(game.legal_moves).to eq({})
    expect(game.status).to eq(check: nil, checkmate: false, stalemate: true)
  end
end
