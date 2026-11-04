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

  describe '#move result payload' do
    it 'returns exactly the documented keys for a quiet move' do
      result = described_class.new.move('g1', 'f3')
      expect(result).to eq(
        fen: 'rnbqkbnr/pppppppp/8/8/8/5N2/PPPPPPPP/RNBQKB1R b KQkq - 1 1',
        last_move: { from: 'g1', to: 'f3' },
        capture: nil,
        secondary: nil,
        promotion: nil,
        check: nil,
        checkmate: false,
        stalemate: false
      )
    end

    it 'reports a black promotion as bQ' do
      game = described_class.new('4k3/8/8/8/8/8/p7/4K3 b - - 0 1')
      expect(game.move('a2', 'a1')[:promotion]).to eq('bQ')
    end

    it 'reports both the capture square and the promotion for a capturing underpromotion' do
      game = described_class.new('1r2k3/P7/8/8/8/8/8/4K3 w - - 0 1')
      result = game.move('a7', 'b8', promotion: 'r')
      expect(result[:capture]).to eq('b8')
      expect(result[:promotion]).to eq('wR')
      expect(game.placement['b8']).to eq('R')
    end

    it 'reports check with the checked king square but no mate' do
      game = described_class.new('4k3/8/8/8/8/8/8/R3K3 w - - 0 1')
      result = game.move('a1', 'a8')
      expect(result.slice(:check, :checkmate, :stalemate)).to eq(check: 'e8', checkmate: false, stalemate: false)
    end

    it 'reports the black castle rook hop as the secondary move' do
      game = described_class.new('4k2r/8/8/8/8/8/8/4K3 b k - 0 1')
      expect(game.move('e8', 'g8')[:secondary]).to eq(from: 'h8', to: 'f8')
      expect(game.fen).to eq('5rk1/8/8/8/8/8/8/4K3 w - - 1 2')
    end

    it 'reports stalemate when the move leaves the opponent without moves or check' do
      game = described_class.new('k7/8/2Q5/8/8/8/8/6K1 w - - 0 1')
      result = game.move('c6', 'b6')
      expect(result.slice(:check, :checkmate, :stalemate)).to eq(check: nil, checkmate: false, stalemate: true)
    end
  end

  describe 'checkmate patterns' do
    it 'detects a back-rank mate' do
      game = described_class.new('6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1')
      result = game.move('a1', 'a8')
      expect(result[:checkmate]).to be true
      expect(result[:check]).to eq('g8')
    end

    it 'detects a smothered mate by a knight' do
      game = described_class.new('6rk/6pp/8/6N1/8/8/8/6K1 w - - 0 1')
      result = game.move('g5', 'f7')
      expect(result[:checkmate]).to be true
      expect(result[:check]).to eq('h8')
    end

    it 'does not call it mate when the checking piece can be captured' do
      game = described_class.new('6k1/5ppp/8/8/8/5b2/8/R5K1 w - - 0 1') # bishop f3 covers a8
      result = game.move('a1', 'a8')
      expect(result[:check]).to eq('g8')
      expect(result[:checkmate]).to be false
    end

    it "detects scholar's mate from the opening" do
      game = described_class.new
      [%w[e2 e4], %w[e7 e5], %w[f1 c4], %w[b8 c6], %w[d1 h5], %w[g8 f6]].each { |f, t| game.move(f, t) }
      result = game.move('h5', 'f7')
      expect(result[:checkmate]).to be true
      expect(result[:capture]).to eq('f7')
      expect(game.fen).to eq('r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4')
    end
  end

  describe '#legal_moves' do
    it 'lists exactly the 20 opening moves as destination squares' do
      moves = described_class.new.legal_moves
      expect(moves.values.sum(&:length)).to eq(20)
      expect(moves['b1']).to contain_exactly('a3', 'c3')
      expect(moves['g1']).to contain_exactly('f3', 'h3')
      expect(moves.keys).not_to include('a1', 'c1', 'd1', 'e1', 'f1', 'h1')
    end
  end

  describe 'error messages' do
    it 'names the empty square' do
      expect { described_class.new.move('d4', 'd5') }.to raise_error(ArgumentError, 'no piece on d4')
    end

    it "names the color that isn't on move" do
      expect { described_class.new.move('d7', 'd5') }.to raise_error(ArgumentError, "it's not black's turn")
    end

    it 'names the illegal move' do
      expect { described_class.new.move('d2', 'd5') }.to raise_error(ArgumentError, 'illegal move d2-d5')
    end

    it 'leaves the position unchanged after a rejected move' do
      game = described_class.new
      expect { game.move('d2', 'd5') }.to raise_error(ArgumentError)
      expect(game.fen).to eq(described_class::STARTING_FEN)
    end
  end
end
