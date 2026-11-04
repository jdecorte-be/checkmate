require 'spec_helper'

# Perft: count every leaf node of the legal-move tree to a fixed depth and
# compare against published reference counts. Any bug in castling, en
# passant, promotion, pins or check evasion changes these numbers.
# Reference values: https://www.chessprogramming.org/Perft_Results
RSpec.describe 'perft (move generation node counts)' do
  def perft(board, depth)
    return 1 if depth.zero?

    Chess::MoveGenerator.legal_moves_for_color(board, board.active_color)
                        .values.flatten
                        .sum { |move| perft(board.apply(move), depth - 1) }
  end

  {
    'the starting position' => [
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', [20, 400, 8902]
    ],
    'Kiwipete (castling, en passant, pins, promotions)' => [
      'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1', [48, 2039]
    ],
    'position 3 (rank pins and discovered checks via en passant)' => [
      '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1', [14, 191, 2812]
    ],
    'position 4 (promotions with check, castling rights for one side only)' => [
      'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1', [6, 264]
    ],
    'position 5 (promotion-capture onto a checking square)' => [
      'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8', [44, 1486]
    ]
  }.each do |name, (fen, counts)|
    counts.each.with_index(1) do |expected, depth|
      it "counts #{expected} nodes at depth #{depth} from #{name}" do
        expect(perft(Chess::Board.from_fen(fen), depth)).to eq(expected)
      end
    end
  end
end
