require 'spec_helper'

RSpec.describe Ai::Engine do
  it 'snaps an arbitrary elo to the nearest supported tier' do
    expect(described_class.new(elo: 1234).elo).to eq(1200)
    expect(described_class.new(elo: 50).elo).to eq(400)
    expect(described_class.new(elo: 9999).elo).to eq(described_class.levels.max)
  end

  it 'exposes the supported elo tiers' do
    expect(described_class.levels).to eq([400, 800, 1200, 1600, 1900, 2200])
  end

  it 'returns nil when the side to move has no legal moves' do
    # fool's mate: white is checkmated
    game = Chess::Game.new('rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3')
    expect(described_class.new.choose_move(game)).to be_nil
  end

  it 'plays the only legal move under double check, even at max blunder chance' do
    game = Chess::Game.new('8/8/8/8/4b3/8/8/r6K w - - 0 1')
    move = described_class.new(elo: 400, rng: Random.new(1)).choose_move(game)
    expect(move).to eq(from: 'h1', to: 'h2', promotion: nil)
  end

  it 'captures a free hanging queen when playing at full strength' do
    game = Chess::Game.new('4k3/8/8/3q4/8/8/8/3RK3 w - - 0 1')
    move = described_class.new(elo: 2200).choose_move(game)
    expect(move).to eq(from: 'd1', to: 'd5', promotion: nil)
  end

  it 'plays correctly for Black too, not just White (catches sign-flip bugs)' do
    game = Chess::Game.new('3rk3/8/8/3Q4/8/8/8/4K3 b - - 0 1')
    move = described_class.new(elo: 2200).choose_move(game)
    expect(move).to eq(from: 'd8', to: 'd5', promotion: nil)
  end

  it 'can blunder away from the best move at a low elo tier' do
    game = Chess::Game.new('4k3/8/8/3q4/8/8/8/3RK3 w - - 0 1')
    best = described_class.new(elo: 2200).choose_move(game)

    # 40% blunder chance per seed; astronomically unlikely all 30 trials miss
    blundered = (0..30).any? do |seed|
      described_class.new(elo: 400, rng: Random.new(seed)).choose_move(game) != best
    end
    expect(blundered).to be true
  end

  it 'snaps a midpoint elo to the lower tier (first match wins a tie)' do
    expect(described_class.new(elo: 1000).elo).to eq(800)
  end

  it 'delivers a back-rank mate in one at full strength' do
    game = Chess::Game.new('6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1')
    expect(described_class.new(elo: 1900).choose_move(game)).to eq(from: 'a1', to: 'a8', promotion: nil)
  end

  it 'promotes to a queen at once when the pawn would otherwise be captured' do
    game = Chess::Game.new('8/r3P3/8/8/8/8/8/4K2k w - - 0 1') # Ra7 takes the pawn if it waits
    expect(described_class.new(elo: 1900).choose_move(game)).to eq(from: 'e7', to: 'e8', promotion: 'q')
  end

  it 'does not grab a pawn with its queen when the pawn is defended by another pawn' do
    game = Chess::Game.new('4k3/8/2p5/3p4/8/8/8/3QK3 w - - 0 1')
    move = described_class.new(elo: 1900).choose_move(game)
    expect([move[:from], move[:to]]).not_to eq(%w[d1 d5])
  end

  it 'escapes when its queen is attacked by a pawn' do
    game = Chess::Game.new('4k3/8/8/2p5/3Q4/8/8/4K3 w - - 0 1')
    move = described_class.new(elo: 1900).choose_move(game)
    after = Chess::Game.new(game.fen).tap { |g| g.move(move[:from], move[:to], promotion: move[:promotion]) }
    queen_square = after.placement.key('Q')
    expect(queen_square).not_to be_nil
    expect(after.board.attacked?(queen_square, 'b')).to be false
  end

  it 'returns the same move for the same seed and tier' do
    game = Chess::Game.new
    first = described_class.new(elo: 800, rng: Random.new(42)).choose_move(game)
    second = described_class.new(elo: 800, rng: Random.new(42)).choose_move(game)
    expect(first).to eq(second)
  end

  it 'never returns an illegal move, across many seeds at the noisiest tier' do
    game = Chess::Game.new('r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3')
    legal = game.legal_moves
    20.times do |seed|
      move = described_class.new(elo: 400, rng: Random.new(seed)).choose_move(game)
      expect(legal.fetch(move[:from])).to include(move[:to])
    end
  end

  describe 'debug payload' do
    it 'reports search stats with candidates sorted best-first and notated as from+to' do
      game = Chess::Game.new('4k3/8/8/3q4/8/8/8/3RK3 w - - 0 1')
      debug = described_class.new(elo: 1900).choose_move(game, debug: true)[:debug]

      expect(debug.keys).to contain_exactly(:elo, :depth, :blunder, :nodes, :elapsedMs, :candidates)
      expect(debug[:elo]).to eq(1900)
      expect(debug[:blunder]).to be false
      expect(debug[:depth]).to be_between(1, 4)
      expect(debug[:nodes]).to be_positive
      expect(debug[:candidates].length).to be <= 8
      expect(debug[:candidates].first[:move]).to eq('d1d5')
      scores = debug[:candidates].map { |c| c[:score] }
      expect(scores).to eq(scores.sort.reverse)
      expect(debug[:candidates].map { |c| c[:move] }).to all(match(/\A[a-h][1-8][a-h][1-8](=[QRBN])?\z/))
    end

    it 'notates promotions with an =PIECE suffix' do
      game = Chess::Game.new('8/r3P3/8/8/8/8/8/4K2k w - - 0 1') # Ra7 takes the pawn if it waits
      moves = described_class.new(elo: 1900).choose_move(game, debug: true)[:debug][:candidates].map { |c| c[:move] }
      expect(moves.first).to eq('e7e8=Q')
    end

    it 'marks a blunder with depth 0 and no candidates' do
      # First rand call (< 0.40 blunder chance) forces the blunder branch.
      rng = Random.new(0)
      allow(rng).to receive(:rand).and_call_original
      allow(rng).to receive(:rand).with(no_args).and_return(0.0)

      result = described_class.new(elo: 400, rng: rng).choose_move(Chess::Game.new, debug: true)
      expect(result[:debug]).to include(depth: 0, candidates: [], blunder: true, elo: 400)
      expect(Chess::Game.new.legal_moves.fetch(result[:from])).to include(result[:to])
    end

    it 'omits the debug key entirely when debug is off' do
      move = described_class.new(elo: 400, rng: Random.new(3)).choose_move(Chess::Game.new)
      expect(move.keys).to eq(%i[from to promotion])
    end
  end
end
