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
end
