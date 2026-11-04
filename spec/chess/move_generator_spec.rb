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

  def dests(fen, from)
    described_class.legal_moves(board_for(fen), from).map(&:to).sort
  end

  describe 'pawns' do
    it 'moves a black pawn toward rank 1, including a double push from rank 7' do
      expect(dests('4k3/3p4/8/8/8/8/8/4K3 b - - 0 1', 'd7')).to eq(%w[d5 d6])
    end

    it 'cannot double push when the square directly ahead is blocked' do
      expect(dests('4k3/8/8/8/8/4n3/4P3/4K3 w - - 0 1', 'e2')).to eq([])
    end

    it 'can single push but not double push when only the landing square is blocked' do
      expect(dests('4k3/8/8/8/4n3/8/4P3/4K3 w - - 0 1', 'e2')).to eq(%w[e3])
    end

    it 'cannot capture straight ahead' do
      expect(dests('4k3/8/8/8/4p3/4P3/8/4K3 w - - 0 1', 'e3')).to eq([])
    end

    it 'does not wrap around the board edge when capturing from the a- or h-file' do
      expect(dests('4k3/8/8/8/8/p6p/P6P/4K3 w - - 0 1', 'a2')).to eq([])
      expect(dests('4k3/8/8/8/8/p6p/P6P/4K3 w - - 0 1', 'h2')).to eq([])
    end

    it 'reports the en passant capture square on the generated move' do
      move = described_class.legal_moves(board_for('4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1'), 'e5')
                            .find { |m| m.to == 'd6' }
      expect(move.en_passant_capture).to eq('d5')
    end

    it 'forbids en passant when removing both pawns would expose the king along the rank' do
      expect(dests('7k/8/8/K2pP2r/8/8/8/8 w - d6 0 1', 'e5')).to eq(%w[e6])
    end

    it 'allows en passant to capture a pawn that is giving check' do
      board = board_for('7k/8/8/3pP3/4K3/8/8/8 w - d6 0 1')
      expect(board.in_check?('w')).to be true
      expect(dests('7k/8/8/3pP3/4K3/8/8/8 w - d6 0 1', 'e5')).to eq(%w[d6])
    end

    it 'generates four promotions per destination for a pawn that can push or capture onto rank 8' do
      moves = described_class.legal_moves(board_for('2r1r2k/3P4/8/8/8/8/8/K7 w - - 0 1'), 'd7')
      expect(moves.map { |m| [m.to, m.promotion] }).to contain_exactly(
        %w[d8 q], %w[d8 r], %w[d8 b], %w[d8 n],
        %w[c8 q], %w[c8 r], %w[c8 b], %w[c8 n],
        %w[e8 q], %w[e8 r], %w[e8 b], %w[e8 n]
      )
    end
  end

  describe 'king safety' do
    it 'never lets the king step onto a square attacked by a pawn' do
      expect(dests('7k/8/8/8/8/3p4/8/4K3 w - - 0 1', 'e1')).to eq(%w[d1 d2 f1 f2])
    end

    it 'does not let the king capture a defended piece' do
      expect(dests('7k/8/8/8/8/8/3q4/3qK3 w - - 0 1', 'e1')).not_to include('d1', 'd2')
    end

    it 'keeps a checked king off the checking file' do
      expect(dests('4r2k/8/8/8/8/8/8/4K3 w - - 0 1', 'e1')).to eq(%w[d1 d2 f1 f2])
    end

    it 'only allows king moves under double check' do
      board = board_for('4k3/8/8/8/1b6/8/8/r3K2N w - - 0 1')
      movable = described_class.legal_moves_for_color(board, 'w').keys
      expect(movable).to eq(%w[e1])
    end

    it 'lets a non-king piece block a single check' do
      expect(dests('4r2k/8/8/8/8/8/8/R3K3 w - - 0 1', 'a1')).to eq([])
      expect(dests('4r2k/8/8/8/8/8/3B4/4K3 w - - 0 1', 'd2')).to eq(%w[e3])
    end

    it 'lets a pinned piece capture the piece pinning it' do
      expect(dests('4k3/8/8/8/7b/8/5B2/4K3 w - - 0 1', 'f2')).to eq(%w[g3 h4])
    end

    it 'gives a pinned knight no moves at all' do
      expect(dests('4k3/4r3/8/8/8/8/4N3/4K3 w - - 0 1', 'e2')).to eq([])
    end
  end

  describe 'castling' do
    it 'allows queenside castling when only b1 (not on the king\'s path) is attacked' do
      expect(dests('1r5k/8/8/8/8/8/8/R3K3 w Q - 0 1', 'e1')).to include('c1')
    end

    it 'forbids queenside castling when d1 is attacked' do
      expect(dests('3r3k/8/8/8/8/8/8/R3K3 w Q - 0 1', 'e1')).not_to include('c1')
    end

    it 'forbids castling into check on g1' do
      expect(dests('6rk/8/8/8/8/8/8/4K2R w K - 0 1', 'e1')).not_to include('g1')
    end

    it 'forbids castling when the right is in the FEN but the rook is gone' do
      expect(dests('7k/8/8/8/8/8/8/4K3 w K - 0 1', 'e1')).not_to include('g1')
    end

    it 'forbids castling when the corner piece is not a rook' do
      expect(dests('7k/8/8/8/8/8/8/4K2N w K - 0 1', 'e1')).not_to include('g1')
    end

    it 'forbids castling without the matching right even with king and rook at home' do
      expect(dests('7k/8/8/8/8/8/8/R3K2R w - - 0 1', 'e1')).not_to include('c1', 'g1')
    end

    it 'generates both black castles with the correct rook hops' do
      moves = described_class.legal_moves(board_for('r3k2r/8/8/8/8/8/8/4K3 b kq - 0 1'), 'e8')
      castles = moves.select(&:castle).to_h { |m| [m.to, [m.castle.rook_from, m.castle.rook_to]] }
      expect(castles).to eq('g8' => %w[h8 f8], 'c8' => %w[a8 d8])
    end
  end

  describe '.find' do
    let(:board) { board_for('4k3/1P6/8/8/8/8/8/4K3 w - - 0 1') }

    it 'defaults a promotion to a queen' do
      expect(described_class.find(board, 'b7', 'b8').promotion).to eq('q')
    end

    it 'accepts an uppercase promotion letter' do
      expect(described_class.find(board, 'b7', 'b8', promotion: 'R').promotion).to eq('r')
    end

    it 'falls back to the first generated promotion for an unknown piece letter' do
      expect(described_class.find(board, 'b7', 'b8', promotion: 'k').promotion).to eq('q')
    end

    it 'returns nil for a destination the piece cannot reach' do
      expect(described_class.find(board, 'b7', 'c8')).to be_nil
    end

    it 'returns nil for an empty origin square' do
      expect(described_class.find(board, 'a1', 'a2')).to be_nil
    end
  end

  describe '.any_legal_moves?' do
    it 'is false for a checkmated side' do
      board = board_for('R5k1/5ppp/8/8/8/8/8/6K1 b - - 0 1')
      expect(described_class.any_legal_moves?(board, 'b')).to be false
    end

    it 'is true when only a single pawn push is available' do
      board = board_for('k7/P7/1K6/8/8/8/7p/8 b - - 0 1')
      expect(described_class.legal_moves_for_color(board, 'b').transform_values { |ms| ms.map(&:to) })
        .to eq('h2' => %w[h1 h1 h1 h1])
      expect(described_class.any_legal_moves?(board, 'b')).to be true
    end
  end
end
