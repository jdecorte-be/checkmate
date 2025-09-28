module Chess
  # Immutable chess position: piece placement plus the rest of FEN state
  # (whose turn, castling rights, en passant target, clocks). `apply`
  # returns a new Board rather than mutating this one, so callers (the
  # move generator, in particular) can simulate a move and check king
  # safety without touching the real game state.
  class Board
    FILES = %w[a b c d e f g h].freeze

    attr_reader :squares, :active_color, :castling, :en_passant, :halfmove, :fullmove

    def initialize(squares:, active_color:, castling:, en_passant:, halfmove:, fullmove:)
      @squares = squares
      @active_color = active_color
      @castling = castling
      @en_passant = en_passant
      @halfmove = halfmove
      @fullmove = fullmove
    end

    def self.from_fen(fen)
      placement, active, castling, en_passant, halfmove, fullmove = fen.split(' ')
      squares = {}
      placement.split('/').each_with_index do |row, rank_index|
        rank = 8 - rank_index
        file = 0
        row.each_char do |char|
          if char =~ /\d/
            file += char.to_i
          else
            squares[FILES[file] + rank.to_s] = char
            file += 1
          end
        end
      end
      new(
        squares: squares,
        active_color: active,
        castling: castling,
        en_passant: en_passant == '-' ? nil : en_passant,
        halfmove: halfmove.to_i,
        fullmove: fullmove.to_i
      )
    end

    def to_fen
      rows = 8.downto(1).map do |rank|
        empty = 0
        row = +''
        FILES.each do |file|
          piece = squares[file + rank.to_s]
          if piece
            row << empty.to_s if empty.positive?
            empty = 0
            row << piece
          else
            empty += 1
          end
        end
        row << empty.to_s if empty.positive?
        row
      end
      [rows.join('/'), active_color, castling, en_passant || '-', halfmove.to_s, fullmove.to_s].join(' ')
    end

    def occupied?(square)
      squares.key?(square)
    end

    def piece_at(square)
      squares[square]
    end

    def white?(piece)
      piece == piece.upcase
    end

    def color_of(square)
      piece = squares[square]
      return nil unless piece

      white?(piece) ? 'w' : 'b'
    end

    def opposite(color)
      color == 'w' ? 'b' : 'w'
    end

    def king_square(color)
      squares.key(color == 'w' ? 'K' : 'k')
    end

    def in_check?(color)
      king = king_square(color)
      return false unless king

      attacked?(king, opposite(color))
    end

    # Is `square` attacked by any piece belonging to `by_color`?
    def attacked?(square, by_color)
      squares.any? do |sq, piece|
        next false unless (white?(piece) ? 'w' : 'b') == by_color

        piece_attacks?(piece, sq, square)
      end
    end

    # Applies a fully-formed Move (as produced by MoveGenerator) and
    # returns the resulting Board. Does not check legality itself.
    def apply(move)
      piece = squares.fetch(move.from)
      capture = occupied?(move.to) || !move.en_passant_capture.nil?

      new_squares = squares.dup
      new_squares.delete(move.from)
      new_squares.delete(move.en_passant_capture) if move.en_passant_capture
      new_squares[move.to] = move.promotion ? promoted_piece(piece, move.promotion) : piece
      if move.castle
        rook = new_squares.delete(move.castle.rook_from)
        new_squares[move.castle.rook_to] = rook
      end

      Board.new(
        squares: new_squares,
        active_color: opposite(active_color),
        castling: updated_castling(move, piece),
        en_passant: double_push_target(move, piece),
        halfmove: (capture || piece.downcase == 'p') ? 0 : halfmove + 1,
        fullmove: active_color == 'b' ? fullmove + 1 : fullmove
      )
    end

    private

    def coords(square)
      [square[0].ord - 97, square[1..].to_i]
    end

    def square(file, rank)
      return nil unless file.between?(0, 7) && rank.between?(1, 8)

      FILES[file] + rank.to_s
    end

    def promoted_piece(piece, promotion)
      white?(piece) ? promotion.upcase : promotion.downcase
    end

    def double_push_target(move, piece)
      return nil unless piece.downcase == 'p'

      from_file, from_rank = coords(move.from)
      _, to_rank = coords(move.to)
      return nil unless (to_rank - from_rank).abs == 2

      square(from_file, (from_rank + to_rank) / 2)
    end

    ROOK_HOME = { 'a1' => 'Q', 'h1' => 'K', 'a8' => 'q', 'h8' => 'k' }.freeze

    def updated_castling(move, piece)
      rights = castling.dup
      rights = rights.delete('KQ') if piece == 'K'
      rights = rights.delete('kq') if piece == 'k'
      rights = rights.delete(ROOK_HOME[move.from]) if ROOK_HOME.key?(move.from)
      rights = rights.delete(ROOK_HOME[move.to]) if ROOK_HOME.key?(move.to)
      rights.empty? ? '-' : rights
    end

    def piece_attacks?(piece, from, target)
      return false if from == target

      file, rank = coords(from)
      tfile, trank = coords(target)
      df = tfile - file
      dr = trank - rank

      case piece.downcase
      when 'p' then dr == (white?(piece) ? 1 : -1) && df.abs == 1
      when 'n' then [df.abs, dr.abs].sort == [1, 2]
      when 'k' then df.abs <= 1 && dr.abs <= 1
      when 'b' then df.abs == dr.abs && df != 0 && clear_path?(from, target)
      when 'r' then (df.zero? ^ dr.zero?) && clear_path?(from, target)
      when 'q' then (df.abs == dr.abs || df.zero? || dr.zero?) && clear_path?(from, target)
      end
    end

    def clear_path?(from, to)
      file, rank = coords(from)
      tfile, trank = coords(to)
      step_f = tfile <=> file
      step_r = trank <=> rank
      f, r = file + step_f, rank + step_r
      until [f, r] == [tfile, trank]
        return false if squares.key?(square(f, r))

        f += step_f
        r += step_r
      end
      true
    end
  end
end
