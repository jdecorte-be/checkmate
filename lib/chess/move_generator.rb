require_relative 'move'

module Chess
  # Generates fully legal moves: pseudo-legal piece movement, filtered to
  # exclude any move that would leave the mover's own king in check.
  module MoveGenerator
    FILES = %w[a b c d e f g h].freeze

    KNIGHT_OFFSETS = [[1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2]].freeze
    KING_OFFSETS = [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]].freeze
    ROOK_DIRS = [[1, 0], [-1, 0], [0, 1], [0, -1]].freeze
    BISHOP_DIRS = [[1, 1], [1, -1], [-1, 1], [-1, -1]].freeze

    module_function

    # All legal moves for the piece on `from`. Empty if there's no piece
    # there, it isn't that color's turn, or it has no legal moves.
    def legal_moves(board, from)
      piece = board.piece_at(from)
      return [] unless piece

      color = board.white?(piece) ? 'w' : 'b'
      return [] unless color == board.active_color

      pseudo_legal_moves(board, from, piece, color).reject do |move|
        board.apply(move).in_check?(color)
      end
    end

    # { square => [Move, ...] } for every piece belonging to `color`
    def legal_moves_for_color(board, color)
      board.squares.each_with_object({}) do |(square, piece), memo|
        next unless (board.white?(piece) ? 'w' : 'b') == color

        moves = legal_moves(board, square)
        memo[square] = moves unless moves.empty?
      end
    end

    def any_legal_moves?(board, color)
      board.squares.any? do |square, piece|
        next false unless (board.white?(piece) ? 'w' : 'b') == color

        legal_moves(board, square).any?
      end
    end

    # The specific legal Move from `from` to `to`, matching `promotion` if
    # given (else defaulting to queen), or nil if there is no such move.
    def find(board, from, to, promotion: nil)
      candidates = legal_moves(board, from).select { |m| m.to == to }
      return nil if candidates.empty?
      return candidates.first unless candidates.first.promotion

      desired = (promotion || 'q').downcase
      candidates.find { |m| m.promotion == desired } || candidates.first
    end

    def pseudo_legal_moves(board, from, piece, color)
      case piece.downcase
      when 'p' then pawn_moves(board, from, color)
      when 'n' then step_moves(board, from, color, KNIGHT_OFFSETS)
      when 'b' then sliding_moves(board, from, color, BISHOP_DIRS)
      when 'r' then sliding_moves(board, from, color, ROOK_DIRS)
      when 'q' then sliding_moves(board, from, color, ROOK_DIRS + BISHOP_DIRS)
      when 'k' then step_moves(board, from, color, KING_OFFSETS) + castling_moves(board, from, color)
      else []
      end
    end

    def step_moves(board, from, color, offsets)
      file, rank = coords(from)
      offsets.each_with_object([]) do |(df, dr), moves|
        to = square(file + df, rank + dr)
        next unless to
        next if board.occupied?(to) && board.color_of(to) == color

        moves << Move.new(from: from, to: to)
      end
    end

    def sliding_moves(board, from, color, directions)
      file, rank = coords(from)
      moves = []
      directions.each do |df, dr|
        f, r = file, rank
        loop do
          f += df
          r += dr
          to = square(f, r)
          break unless to

          if board.occupied?(to)
            moves << Move.new(from: from, to: to) if board.color_of(to) != color
            break
          else
            moves << Move.new(from: from, to: to)
          end
        end
      end
      moves
    end

    def pawn_moves(board, from, color)
      moves = []
      file, rank = coords(from)
      dir = color == 'w' ? 1 : -1
      start_rank = color == 'w' ? 2 : 7
      last_rank = color == 'w' ? 8 : 1

      one = square(file, rank + dir)
      if one && !board.occupied?(one)
        moves.concat(promotions_for(from, one, nil, last_rank))
        if rank == start_rank
          two = square(file, rank + (2 * dir))
          moves << Move.new(from: from, to: two) if two && !board.occupied?(two)
        end
      end

      [-1, 1].each do |df|
        to = square(file + df, rank + dir)
        next unless to

        if board.occupied?(to) && board.color_of(to) != color
          moves.concat(promotions_for(from, to, nil, last_rank))
        elsif board.en_passant == to
          moves << Move.new(from: from, to: to, en_passant_capture: square(file + df, rank))
        end
      end

      moves
    end

    def promotions_for(from, to, en_passant_capture, last_rank)
      _, target_rank = coords(to)
      if target_rank == last_rank
        %w[q r b n].map { |p| Move.new(from: from, to: to, promotion: p, en_passant_capture: en_passant_capture) }
      else
        [Move.new(from: from, to: to, en_passant_capture: en_passant_capture)]
      end
    end

    def castling_moves(board, from, color)
      return [] if board.in_check?(color)

      opponent = board.opposite(color)
      rank = color == 'w' ? '1' : '8'
      moves = []

      if board.castling.include?(color == 'w' ? 'K' : 'k')
        f, g, h = "f#{rank}", "g#{rank}", "h#{rank}"
        if !board.occupied?(f) && !board.occupied?(g) &&
           board.piece_at(h)&.downcase == 'r' &&
           !board.attacked?(f, opponent) && !board.attacked?(g, opponent)
          moves << Move.new(from: from, to: g, castle: { rook_from: h, rook_to: f })
        end
      end

      if board.castling.include?(color == 'w' ? 'Q' : 'q')
        a, b, c, d = "a#{rank}", "b#{rank}", "c#{rank}", "d#{rank}"
        if !board.occupied?(b) && !board.occupied?(c) && !board.occupied?(d) &&
           board.piece_at(a)&.downcase == 'r' &&
           !board.attacked?(d, opponent) && !board.attacked?(c, opponent)
          moves << Move.new(from: from, to: c, castle: { rook_from: a, rook_to: d })
        end
      end

      moves
    end

    def coords(square)
      [square[0].ord - 97, square[1..].to_i]
    end

    def square(file, rank)
      return nil unless file.between?(0, 7) && rank.between?(1, 8)

      FILES[file] + rank.to_s
    end
  end
end
