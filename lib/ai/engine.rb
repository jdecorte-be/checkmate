require_relative '../chess/move_generator'

module Ai
  # Depth-limited negamax search with alpha-beta pruning and a material +
  # piece-square-table evaluation. Strength is tuned via `elo`, snapped to
  # the nearest of a few discrete tiers below - these are illustrative
  # labels, not a calibrated rating (there's no rating pool to calibrate
  # against). Weaker tiers search less deep, occasionally play a random
  # legal move outright ("blunder"), and add random noise to move scores
  # so they don't always find their single best move even when they do
  # search.
  class Engine
    MATE_SCORE = 1_000_000

    # depth 4 measured ~14s/move from the opening position in this pure-Ruby
    # search (vs. ~1.3s at depth 3) - too slow for a synchronous HTTP
    # request, so 3 plies is the practical ceiling for now.
    LEVELS = [
      { elo: 400,  depth: 1, blunder: 0.40, noise: 150 },
      { elo: 800,  depth: 1, blunder: 0.15, noise: 100 },
      { elo: 1200, depth: 2, blunder: 0.08, noise: 60 },
      { elo: 1600, depth: 2, blunder: 0.02, noise: 30 },
      { elo: 1900, depth: 3, blunder: 0.0,  noise: 15 },
      { elo: 2200, depth: 3, blunder: 0.0,  noise: 0 }
    ].freeze

    PIECE_VALUES = { 'p' => 100, 'n' => 320, 'b' => 330, 'r' => 500, 'q' => 900, 'k' => 0 }.freeze

    PAWN_PST = [
      0,   0,   0,   0,   0,   0,   0,   0,
      50,  50,  50,  50,  50,  50,  50,  50,
      10,  10,  20,  30,  30,  20,  10,  10,
      5,   5,  10,  25,  25,  10,   5,   5,
      0,   0,   0,  20,  20,   0,   0,   0,
      5,  -5, -10,   0,   0, -10,  -5,   5,
      5,  10,  10, -20, -20,  10,  10,   5,
      0,   0,   0,   0,   0,   0,   0,   0
    ].freeze

    KNIGHT_PST = [
      -50, -40, -30, -30, -30, -30, -40, -50,
      -40, -20,   0,   0,   0,   0, -20, -40,
      -30,   0,  10,  15,  15,  10,   0, -30,
      -30,   5,  15,  20,  20,  15,   5, -30,
      -30,   0,  15,  20,  20,  15,   0, -30,
      -30,   5,  10,  15,  15,  10,   5, -30,
      -40, -20,   0,   5,   5,   0, -20, -40,
      -50, -40, -30, -30, -30, -30, -40, -50
    ].freeze

    BISHOP_PST = [
      -20, -10, -10, -10, -10, -10, -10, -20,
      -10,   0,   0,   0,   0,   0,   0, -10,
      -10,   0,   5,  10,  10,   5,   0, -10,
      -10,   5,   5,  10,  10,   5,   5, -10,
      -10,   0,  10,  10,  10,  10,   0, -10,
      -10,  10,  10,  10,  10,  10,  10, -10,
      -10,   5,   0,   0,   0,   0,   5, -10,
      -20, -10, -10, -10, -10, -10, -10, -20
    ].freeze

    ROOK_PST = [
      0,   0,   0,   0,   0,   0,   0,   0,
      5,  10,  10,  10,  10,  10,  10,   5,
      -5,   0,   0,   0,   0,   0,   0,  -5,
      -5,   0,   0,   0,   0,   0,   0,  -5,
      -5,   0,   0,   0,   0,   0,   0,  -5,
      -5,   0,   0,   0,   0,   0,   0,  -5,
      -5,   0,   0,   0,   0,   0,   0,  -5,
      0,   0,   0,   5,   5,   0,   0,   0
    ].freeze

    QUEEN_PST = [
      -20, -10, -10,  -5,  -5, -10, -10, -20,
      -10,   0,   0,   0,   0,   0,   0, -10,
      -10,   0,   5,   5,   5,   5,   0, -10,
      -5,   0,   5,   5,   5,   5,   0,  -5,
      0,   0,   5,   5,   5,   5,   0,  -5,
      -10,   5,   5,   5,   5,   5,   0, -10,
      -10,   0,   5,   0,   0,   0,   0, -10,
      -20, -10, -10,  -5,  -5, -10, -10, -20
    ].freeze

    KING_PST = [
      -30, -40, -40, -50, -50, -40, -40, -30,
      -30, -40, -40, -50, -50, -40, -40, -30,
      -30, -40, -40, -50, -50, -40, -40, -30,
      -30, -40, -40, -50, -50, -40, -40, -30,
      -20, -30, -30, -40, -40, -30, -30, -20,
      -10, -20, -20, -20, -20, -20, -20, -10,
      20,  20,   0,   0,   0,   0,  20,  20,
      20,  30,  10,   0,   0,  10,  30,  20
    ].freeze

    PST = { 'p' => PAWN_PST, 'n' => KNIGHT_PST, 'b' => BISHOP_PST, 'r' => ROOK_PST, 'q' => QUEEN_PST, 'k' => KING_PST }.freeze

    def self.levels
      LEVELS.map { |l| l[:elo] }
    end

    def initialize(elo: 1200, rng: Random.new)
      @level = LEVELS.min_by { |l| (l[:elo] - elo).abs }
      @rng = rng
    end

    def elo
      @level[:elo]
    end

    # { from:, to:, promotion: } for the chosen move, or nil if the side to
    # move has no legal moves (checkmate/stalemate).
    def choose_move(game)
      board = game.board
      moves = all_moves(board, board.active_color)
      return nil if moves.empty?

      if @rng.rand < @level[:blunder]
        move = moves.sample(random: @rng)
        return { from: move.from, to: move.to, promotion: move.promotion }
      end

      best = moves.max_by do |move|
        -negamax(board.apply(move), @level[:depth] - 1, -Float::INFINITY, Float::INFINITY) + noise
      end
      { from: best.from, to: best.to, promotion: best.promotion }
    end

    private

    def negamax(board, depth, alpha, beta)
      color = board.active_color
      moves = all_moves(board, color)
      return board.in_check?(color) ? -(MATE_SCORE + depth) : 0 if moves.empty?
      return perspective(color) * evaluate(board) if depth.zero?

      best = -Float::INFINITY
      order(board, moves).each do |move|
        score = -negamax(board.apply(move), depth - 1, -beta, -alpha)
        best = score if score > best
        alpha = score if score > alpha
        break if alpha >= beta
      end
      best
    end

    def noise
      return 0 if @level[:noise].zero?

      @rng.rand(-@level[:noise]..@level[:noise])
    end

    # Captures first, for better alpha-beta cutoffs.
    def order(board, moves)
      moves.sort_by { |m| board.occupied?(m.to) ? 0 : 1 }
    end

    def all_moves(board, color)
      Chess::MoveGenerator.legal_moves_for_color(board, color).values.flatten
    end

    def perspective(color)
      color == 'w' ? 1 : -1
    end

    def evaluate(board)
      board.squares.sum do |square, piece|
        type = piece.downcase
        value = PIECE_VALUES.fetch(type) + pst_value(type, square, board.white?(piece))
        board.white?(piece) ? value : -value
      end
    end

    def pst_value(type, square, white)
      file = square[0].ord - 97
      rank = square[1..].to_i
      row = white ? 8 - rank : rank - 1
      PST.fetch(type)[(row * 8) + file]
    end
  end
end
