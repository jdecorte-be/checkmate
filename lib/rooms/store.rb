require 'securerandom'
require_relative '../chess/game'

module Rooms
  # A single 1v1 game, joined by sharing a short code. Lives only in process
  # memory — there's no database, so rooms don't survive a restart.
  class Room
    # Excludes 0/O and 1/I, which are easy to mix up when read aloud or typed.
    CODE_CHARS = (('A'..'Z').to_a + ('0'..'9').to_a - %w[0 O 1 I]).freeze
    CODE_LENGTH = 5

    attr_reader :code, :white_token, :created_at
    attr_accessor :black_token, :fen, :version, :last_move

    def initialize(code)
      @code = code
      @fen = Chess::Game::STARTING_FEN
      @white_token = SecureRandom.hex(16)
      @black_token = nil
      @version = 0
      @last_move = nil
      @created_at = Time.now
    end

    def full?
      !black_token.nil?
    end

    def status
      full? ? 'active' : 'waiting'
    end

    def color_for(token)
      return nil if token.nil?
      return 'white' if token == white_token
      return 'black' if token == black_token

      nil
    end
  end

  # Thread-safe registry of in-progress rooms, keyed by their share code.
  class Store
    MAX_AGE = 60 * 60 * 12 # sweep rooms idle for more than 12h

    def initialize
      @rooms = {}
      @mutex = Mutex.new
    end

    def create
      @mutex.synchronize do
        sweep_stale
        code = unique_code
        @rooms[code] = Room.new(code)
      end
    end

    def find(code)
      return nil if code.nil?

      @mutex.synchronize { @rooms[code.upcase] }
    end

    # Assigns the joining player as black. Returns [room, token], or
    # [room, nil] if the room is already full.
    def join(code)
      @mutex.synchronize do
        room = @rooms[code&.upcase]
        return [nil, nil] unless room
        return [room, nil] if room.full?

        token = SecureRandom.hex(16)
        room.black_token = token
        [room, token]
      end
    end

    def apply_move(room, fen, response)
      @mutex.synchronize do
        room.fen = fen
        room.version += 1
        room.last_move = response.merge(version: room.version)
      end
    end

    private

    def unique_code
      loop do
        code = Array.new(Room::CODE_LENGTH) { Room::CODE_CHARS.sample }.join
        break code unless @rooms.key?(code)
      end
    end

    def sweep_stale
      cutoff = Time.now - MAX_AGE
      @rooms.delete_if { |_, room| room.created_at < cutoff }
    end
  end
end
