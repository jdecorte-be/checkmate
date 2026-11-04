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

  describe '.from_fen' do
    it "stores '-' en passant as nil and parses clocks as integers" do
      board = described_class.from_fen('4k3/8/8/8/8/8/8/4K3 b - - 17 42')
      expect(board.en_passant).to be_nil
      expect(board.halfmove).to eq(17)
      expect(board.fullmove).to eq(42)
      expect(board.active_color).to eq('b')
    end

    it 'maps each FEN character onto the exact square' do
      board = described_class.from_fen('r6k/8/8/8/3Q4/8/8/K6R w - - 0 1')
      expect(board.squares).to eq('a8' => 'r', 'h8' => 'k', 'd4' => 'Q', 'a1' => 'K', 'h1' => 'R')
    end

    it 'round-trips an empty-castling, high-move-count FEN unchanged' do
      fen = '8/5k2/8/8/8/8/2K5/8 w - - 99 150'
      expect(described_class.from_fen(fen).to_fen).to eq(fen)
    end
  end

  describe '#apply' do
    it 'does not mutate the board it is called on' do
      board = described_class.from_fen(Chess::Game::STARTING_FEN)
      board.apply(Chess::Move.new(from: 'e2', to: 'e4'))
      expect(board.to_fen).to eq(Chess::Game::STARTING_FEN)
    end

    it 'sets the en passant target to the skipped square after a white double push' do
      board = described_class.from_fen(Chess::Game::STARTING_FEN)
      expect(board.apply(Chess::Move.new(from: 'c2', to: 'c4')).en_passant).to eq('c3')
    end

    it 'sets the en passant target to the skipped square after a black double push' do
      board = described_class.from_fen('rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1')
      expect(board.apply(Chess::Move.new(from: 'h7', to: 'h5')).en_passant).to eq('h6')
    end

    it 'clears the en passant target after a single pawn push' do
      board = described_class.from_fen('4k3/8/8/8/8/8/4P3/4K3 w - d6 0 1')
      expect(board.apply(Chess::Move.new(from: 'e2', to: 'e3')).en_passant).to be_nil
    end

    it 'clears the en passant target after a non-pawn move that spans two ranks' do
      board = described_class.from_fen('4k3/8/8/8/8/8/8/4K1N1 w - - 0 1')
      expect(board.apply(Chess::Move.new(from: 'g1', to: 'f3')).en_passant).to be_nil
    end

    it 'drops both of white\'s castling rights when the white king moves' do
      board = described_class.from_fen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1')
      expect(board.apply(Chess::Move.new(from: 'e1', to: 'f1')).castling).to eq('kq')
    end

    it 'drops only the kingside right when the h8 rook moves' do
      board = described_class.from_fen('r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1')
      expect(board.apply(Chess::Move.new(from: 'h8', to: 'h5')).castling).to eq('KQq')
    end

    it "writes '-' once the last castling right is gone" do
      board = described_class.from_fen('4k3/8/8/8/8/8/8/4K2R w K - 0 1')
      after = board.apply(Chess::Move.new(from: 'h1', to: 'h2'))
      expect(after.castling).to eq('-')
      expect(after.to_fen).to eq('4k3/8/8/8/8/8/7R/4K3 b - - 1 1')
    end

    it 'moves the rook alongside the king for a castle move' do
      board = described_class.from_fen('r3k3/8/8/8/8/8/8/4K3 b q - 0 1')
      castle = Chess::Castle.new(rook_from: 'a8', rook_to: 'd8')
      after = board.apply(Chess::Move.new(from: 'e8', to: 'c8', castle: castle))
      expect(after.squares).to eq('c8' => 'k', 'd8' => 'r', 'e1' => 'K')
      expect(after.castling).to eq('-')
    end

    it 'removes the pawn on the en passant capture square, not the destination' do
      board = described_class.from_fen('4k3/8/8/8/3pP3/8/8/4K3 b - e3 0 1')
      after = board.apply(Chess::Move.new(from: 'd4', to: 'e3', en_passant_capture: 'e4'))
      expect(after.piece_at('e3')).to eq('p')
      expect(after.occupied?('e4')).to be false
      expect(after.occupied?('d4')).to be false
    end

    it 'resets the halfmove clock on an en passant capture' do
      board = described_class.from_fen('4k3/8/8/3pP3/8/8/8/4K3 w - d6 12 30')
      after = board.apply(Chess::Move.new(from: 'e5', to: 'd6', en_passant_capture: 'd5'))
      expect(after.halfmove).to eq(0)
    end

    it 'promotes a black pawn to a lowercase piece' do
      board = described_class.from_fen('4k3/8/8/8/8/8/3p4/K7 b - - 0 1')
      after = board.apply(Chess::Move.new(from: 'd2', to: 'd1', promotion: 'n'))
      expect(after.piece_at('d1')).to eq('n')
      expect(after.occupied?('d2')).to be false
    end

    it 'increments the fullmove number only after black moves' do
      white_to_move = described_class.from_fen('4k3/8/8/8/8/8/8/4K3 w - - 0 7')
      after_white = white_to_move.apply(Chess::Move.new(from: 'e1', to: 'd1'))
      expect(after_white.fullmove).to eq(7)
      after_black = after_white.apply(Chess::Move.new(from: 'e8', to: 'd8'))
      expect(after_black.fullmove).to eq(8)
    end
  end

  describe '#attacked?' do
    it 'has a white pawn attack only its two forward diagonals, not the square ahead' do
      board = described_class.from_fen('4k3/8/8/8/4P3/8/8/4K3 w - - 0 1')
      expect(board.attacked?('d5', 'w')).to be true
      expect(board.attacked?('f5', 'w')).to be true
      expect(board.attacked?('e5', 'w')).to be false
      expect(board.attacked?('d3', 'w')).to be false
    end

    it 'has a black pawn attack downward diagonals' do
      board = described_class.from_fen('4k3/8/8/4p3/8/8/8/4K3 w - - 0 1')
      expect(board.attacked?('d4', 'b')).to be true
      expect(board.attacked?('f4', 'b')).to be true
      expect(board.attacked?('d6', 'b')).to be false
    end

    it 'has a knight attack exactly its eight L-shaped squares' do
      board = described_class.from_fen('7k/8/8/8/3N4/8/8/K7 w - - 0 1')
      attacked = Chess::Board::FILES.product((1..8).to_a).map { |f, r| "#{f}#{r}" }
                                    .select { |sq| board.attacked?(sq, 'w') && !%w[a2 b1 b2].include?(sq) }
      expect(attacked).to contain_exactly('b3', 'b5', 'c2', 'c6', 'e2', 'e6', 'f3', 'f5')
    end

    it 'does not let a rook attack diagonally or a bishop attack orthogonally' do
      board = described_class.from_fen('7k/8/8/8/3R4/8/8/K5B1 w - - 0 1')
      expect(board.attacked?('e5', 'w')).to be false # diagonal from the rook
      expect(board.attacked?('g4', 'w')).to be true  # rook along the rank
      expect(board.attacked?('g2', 'w')).to be false # orthogonal from the bishop
      expect(board.attacked?('h2', 'w')).to be true  # bishop along the diagonal
    end

    it 'does not count a piece as attacking its own square' do
      board = described_class.from_fen('7k/8/8/8/3Q4/8/8/K7 w - - 0 1')
      expect(board.attacked?('d4', 'w')).to be false
    end
  end

  describe '#in_check?' do
    it 'is false when that color has no king on the board' do
      board = described_class.from_fen('4k3/8/8/8/8/8/8/4R3 w - - 0 1')
      expect(board.king_square('w')).to be_nil
      expect(board.in_check?('w')).to be false
    end

    it 'detects a knight check that no blocker can stop' do
      board = described_class.from_fen('4k3/8/3N4/8/8/8/8/4K3 b - - 0 1')
      expect(board.in_check?('b')).to be true
    end

    it 'detects a check from an adjacent pawn diagonal but not from one straight ahead' do
      expect(described_class.from_fen('8/8/8/8/8/3p4/4K3/7k w - - 0 1').in_check?('w')).to be true
      expect(described_class.from_fen('8/8/8/8/8/4p3/4K3/7k w - - 0 1').in_check?('w')).to be false
    end
  end
end
