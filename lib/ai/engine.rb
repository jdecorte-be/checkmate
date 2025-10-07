require_relative '../chess/move_generator'

module Ai
  # Negamax + alpha-beta, scored on material and piece-square tables.
  # The elo tiers are just rough labels. Lower tiers search shallower,
  # sometimes play a random move, and add noise to their scores.
  class Engine
    MATE_SCORE = 1_000_000

    # Extra capture-only plies past the main depth (see `quiescence`).
    # Kept small since move generation is the expensive part.
    QUIESCENCE_PLIES = 3

    # Skip captures that can't possibly raise alpha, even if they win the piece for free.
    DELTA_MARGIN = 200

    # Check the clock every N nodes and bail out mid-search once time's up.
    NODES_PER_TIME_CHECK = 1024

    # Thrown when time runs out; we fall back to the last finished depth.
    SearchTimeout = Class.new(StandardError)

    # Iterative deepening up to max_depth, stopping early if time_budget
    # (seconds) runs out so the request doesn't hang.
    LEVELS = [
      { elo: 400,  max_depth: 1, blunder: 0.40, noise: 150, time_budget: 1.0 },
      { elo: 800,  max_depth: 2, blunder: 0.15, noise: 100, time_budget: 1.0 },
      { elo: 1200, max_depth: 2, blunder: 0.08, noise: 60,  time_budget: 1.5 },
      { elo: 1600, max_depth: 3, blunder: 0.02, noise: 30,  time_budget: 2.5 },
      { elo: 1900, max_depth: 4, blunder: 0.0,  noise: 15,  time_budget: 4.0 },
      { elo: 2200, max_depth: 5, blunder: 0.0,  noise: 0,   time_budget: 6.0 }
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

    # Returns { from:, to:, promotion: }, or nil if there are no legal moves.
    # debug: true adds search stats for the debug panel.
    def choose_move(game, debug: false)
      board = game.board
      moves = all_moves(board, board.active_color)
      return nil if moves.empty?

      @nodes = 0
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      if @rng.rand < @level[:blunder]
        move = moves.sample(random: @rng)
        result = { from: move.from, to: move.to, promotion: move.promotion }
        result[:debug] = debug_info(blunder: true, candidates: [], depth: 0, started_at: started_at) if debug
        return result
      end

      scored, depth_reached = search(board, moves, started_at)
      scored = scored.map { |(move, score)| [move, score + noise] }
      best_move, = scored.max_by { |(_move, score)| score }

      result = { from: best_move.from, to: best_move.to, promotion: best_move.promotion }
      if debug
        candidates = scored.sort_by { |(_move, score)| -score }.first(8).map do |move, score|
          { move: notate(move), score: score }
        end
        result[:debug] = debug_info(blunder: false, candidates: candidates, depth: depth_reached, started_at: started_at)
      end
      result
    end

    private

    # Search depth 1, 2, 3... trying the previous best move first each time.
    # Returns the last depth that finished before the deadline.
    def search(board, moves, started_at)
      @deadline = started_at + @level[:time_budget]
      scored = moves.map { |m| [m, 0] }
      best_move = nil
      depth_reached = 0

      (1..@level[:max_depth]).each do |depth|
        break if depth > 1 && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= @deadline

        begin
          scored = order_root(board, moves, best_move).map do |move|
            [move, -negamax(board.apply(move), depth - 1, -Float::INFINITY, Float::INFINITY)]
          end
        rescue SearchTimeout
          break
        end

        best_move, = scored.max_by { |(_move, score)| score }
        depth_reached = depth
      end

      [scored, depth_reached]
    end

    def check_time!
      return unless (@nodes % NODES_PER_TIME_CHECK).zero?
      raise SearchTimeout if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= @deadline
    end

    # Search the previous iteration's best move first.
    def order_root(board, moves, preferred)
      ordered = order(board, moves)
      return ordered unless preferred

      [preferred] + ordered.reject { |m| m == preferred }
    end

    def debug_info(blunder:, candidates:, depth:, started_at:)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
      {
        elo: @level[:elo],
        depth: depth,
        blunder: blunder,
        nodes: @nodes,
        elapsedMs: (elapsed * 1000).round(1),
        candidates: candidates
      }
    end

    def notate(move)
      text = "#{move.from}#{move.to}"
      text += "=#{move.promotion.upcase}" if move.promotion
      text
    end

    def negamax(board, depth, alpha, beta)
      @nodes += 1
      check_time!
      return quiescence(board, alpha, beta, QUIESCENCE_PLIES) if depth.zero?

      color = board.active_color
      moves = all_moves(board, color)
      return board.in_check?(color) ? -(MATE_SCORE + depth) : 0 if moves.empty?

      best = -Float::INFINITY
      order(board, moves).each do |move|
        score = -negamax(board.apply(move), depth - 1, -beta, -alpha)
        best = score if score > best
        alpha = score if score > alpha
        break if alpha >= beta
      end
      best
    end

    # Keep searching captures (or check evasions) until things calm down,
    # so we don't think a piece is free when the recapture is one ply away.
    def quiescence(board, alpha, beta, plies_left)
      @nodes += 1
      check_time!
      color = board.active_color
      in_check = board.in_check?(color)

      if in_check
        moves = all_moves(board, color)
        return -(MATE_SCORE + plies_left) if moves.empty?
        return perspective(color) * evaluate(board) if plies_left.zero?

        best = -Float::INFINITY
        order(board, moves).each do |move|
          score = -quiescence(board.apply(move), -beta, -alpha, plies_left - 1)
          best = score if score > best
          alpha = score if score > alpha
          break if alpha >= beta
        end
        return best
      end

      stand_pat = perspective(color) * evaluate(board)
      return stand_pat if plies_left.zero?
      return beta if stand_pat >= beta

      alpha = stand_pat if stand_pat > alpha
      captures = all_moves(board, color).select { |m| capture?(board, m) }
      order(board, captures).each do |move|
        next if stand_pat + capture_value(board, move) + DELTA_MARGIN < alpha

        score = -quiescence(board.apply(move), -beta, -alpha, plies_left - 1)
        return beta if score >= beta
        alpha = score if score > alpha
      end
      alpha
    end

    def capture_value(board, move)
      victim = board.piece_at(move.to) || 'p'
      PIECE_VALUES.fetch(victim.downcase)
    end

    def noise
      return 0 if @level[:noise].zero?

      @rng.rand(-@level[:noise]..@level[:noise])
    end

    def capture?(board, move)
      board.occupied?(move.to) || !move.en_passant_capture.nil?
    end

    # MVV-LVA: best captures first, quiet moves after.
    def order(board, moves)
      moves.sort_by { |m| -mvv_lva(board, m) }
    end

    def mvv_lva(board, move)
      return 0 unless capture?(board, move)

      attacker = board.piece_at(move.from)
      (capture_value(board, move) * 16) - PIECE_VALUES.fetch(attacker.downcase)
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
