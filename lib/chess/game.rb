require_relative 'board'
require_relative 'move_generator'

module Chess
  # Wraps a single game's position and enforces full move legality: piece
  # movement rules, check safety, castling, en passant, and promotion.
  class Game
    STARTING_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'.freeze

    attr_reader :board

    def initialize(fen = STARTING_FEN)
      @board = Board.from_fen(fen)
    end

    def fen
      board.to_fen
    end

    def active_color
      board.active_color == 'w' ? 'white' : 'black'
    end

    # { "e2" => "P", "e7" => "p", ... }
    def placement
      board.squares.dup
    end

    # { "e2" => ["e3", "e4"], ... } for every piece belonging to the side to move
    def legal_moves
      MoveGenerator.legal_moves_for_color(board, board.active_color)
                   .transform_values { |moves| moves.map(&:to) }
    end

    # check/checkmate/stalemate for the current position, with no move applied
    def status
      color = board.active_color
      in_check = board.in_check?(color)
      has_moves = MoveGenerator.any_legal_moves?(board, color)
      {
        check: in_check ? board.king_square(color) : nil,
        checkmate: in_check && !has_moves,
        stalemate: !in_check && !has_moves
      }
    end

    def move(from, to, promotion: nil)
      mover_color = board.color_of(from)
      raise ArgumentError, "no piece on #{from}" unless mover_color
      raise ArgumentError, "it's not #{mover_color == 'w' ? 'white' : 'black'}'s turn" unless mover_color == board.active_color

      legal = MoveGenerator.find(board, from, to, promotion: promotion)
      raise ArgumentError, "illegal move #{from}-#{to}" unless legal

      capture_square = legal.en_passant_capture || (board.occupied?(to) ? to : nil)
      @board = board.apply(legal)

      {
        fen: fen,
        last_move: { from: from, to: to },
        capture: capture_square,
        secondary: legal.castle ? { from: legal.castle[:rook_from], to: legal.castle[:rook_to] } : nil,
        promotion: legal.promotion && "#{mover_color}#{legal.promotion.upcase}",
        **status
      }
    end
  end
end
