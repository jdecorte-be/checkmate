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

    # Extra capture-only plies searched past the nominal depth, to avoid
    # the horizon effect (e.g. grabbing a pawn that's defended by a piece
    # just past the search cutoff). See `quiescence`. Kept modest because
    # legal-move generation (needed to filter to legal captures) is the
    # search's dominant cost per node - a deep quiescence horizon in a
    # capture-heavy middlegame can outweigh the main search entirely.
    QUIESCENCE_PLIES = 4

    # Skips a quiescence capture outright when even winning the captured
    # piece for free couldn't come close to raising alpha (plus a margin
    # for follow-up tactics). Cuts the many hopeless captures a
    # capture-heavy position offers without recursing into them.
    DELTA_MARGIN = 200

    # How often (in visited nodes) the search checks the wall clock
    # against its deadline. Node cost varies a lot by position (a
    # captures-heavy middlegame is far pricier per node than a sparse
    # endgame), so predicting whether the next iterative-deepening depth
    # will fit the time budget isn't reliable - instead the search
    # aborts itself mid-iteration once time is up (see `check_time!`).
    NODES_PER_TIME_CHECK = 1024

    # Raised to unwind out of an in-progress iteration once its deadline
    # passes; the iteration's (possibly incomplete) scores are discarded
    # in favor of the last iteration that finished cleanly.
    SearchTimeout = Class.new(StandardError)

    # `max_depth` is searched via iterative deepening (depth 1, 2, ...),
    # reusing each completed depth's best move to order the next and
    # bailing out once `time_budget` (seconds) is spent - so search goes
    # as deep as the position allows without blocking the synchronous
    # HTTP request indefinitely. Quiescence search extends tactical lines
    # (captures, check evasions) past `max_depth` regardless of budget.
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

    # { from:, to:, promotion: } for the chosen move, or nil if the side to
    # move has no legal moves (checkmate/stalemate). Pass debug: true to
    # also get a :debug key with search stats and per-candidate scores,
    # for a "what was the AI thinking" view.
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

    # Iterative deepening from the root: searches depth 1, then 2, and so
    # on, re-ordering each iteration around the previous one's best move
    # (a much better guess than capture-first alone, so alpha-beta prunes
    # harder at deeper iterations). Stops once the level's max depth is
    # hit, or once `@deadline` passes (checked periodically inside the
    # search itself - see `check_time!`), always returning the last
    # iteration that finished cleanly.
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

    # Extends the search past the nominal depth along "noisy" lines only
    # (captures, and any move while in check) until the position settles
    # down or `plies_left` runs out. Without this, the engine would
    # regularly misjudge a capture as free simply because the recapture
    # happened to fall just past the search horizon.
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

    # Most Valuable Victim - Least Valuable Attacker: captures first
    # (better ones first) for the best alpha-beta cutoffs, quiet moves
    # after in their original (roughly central-first) order.
    def order(board, moves)
      moves.sort_by { |m| -mvv_lva(board, m) }
    end

    def mvv_lva(board, move)
      return 0 unless capture?(board, move)

      victim = board.piece_at(move.to) || (board.white?(board.piece_at(move.from)) ? 'p' : 'P')
      attacker = board.piece_at(move.from)
      (PIECE_VALUES.fetch(victim.downcase) * 16) - PIECE_VALUES.fetch(attacker.downcase)
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
