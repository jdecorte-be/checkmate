require 'securerandom'
require_relative '../chess/game'

module Rooms
  # A single 1v1 game, joined by sharing a short code. Lives only in process
  # memory — there's no database, so rooms don't survive a restart.
  class Room
    # Excludes 0/O and 1/I, which are easy to mix up when read aloud or typed.
    CODE_CHARS = (('A'..'Z').to_a + ('0'..'9').to_a - %w[0 O 1 I]).freeze
    CODE_LENGTH = 5
    TIME_LIMIT_MS = 10 * 60 * 1000 # 10 minutes per side

    attr_reader :code, :white_token, :created_at
    attr_accessor :black_token, :fen, :version, :last_move, :clock, :turn_started_at, :result

    def initialize(code)
      @code = code
      @fen = Chess::Game::STARTING_FEN
      @white_token = SecureRandom.hex(16)
      @black_token = nil
      @version = 0
      @last_move = nil
      @created_at = Time.now
      @clock = { 'white' => TIME_LIMIT_MS, 'black' => TIME_LIMIT_MS }
      @turn_started_at = nil # the game's clock doesn't run until both players are in
      @result = nil
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

    # Remaining time for `color`, accounting for time elapsed on the clock
    # that's currently running (whichever color's turn it is).
    def remaining_ms(color, active_color, now: Time.now)
      base = clock[color]
      return base unless color == active_color && turn_started_at && !result

      elapsed = ((now - turn_started_at) * 1000).to_i
      [base - elapsed, 0].max
    end

    def clocks(active_color)
      { 'white' => remaining_ms('white', active_color), 'black' => remaining_ms('black', active_color) }
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
        room.turn_started_at = Time.now
        [room, token]
      end
    end

    def apply_move(room, fen, response, mover_color, game_over:)
      @mutex.synchronize do
        if room.turn_started_at
          elapsed = ((Time.now - room.turn_started_at) * 1000).to_i
          room.clock[mover_color] = [room.clock[mover_color] - elapsed, 0].max
        end
        room.fen = fen
        room.version += 1
        room.last_move = response.merge(version: room.version)
        room.turn_started_at = game_over ? nil : Time.now
      end
    end

    # Checks whether the side to move has run out of time and, if so,
    # records the result. Returns the (possibly pre-existing) result, or nil.
    def check_timeout!(room, active_color)
      @mutex.synchronize do
        next room.result unless room.result.nil? && room.full? && room.turn_started_at

        next nil if room.remaining_ms(active_color, active_color) > 0

        room.clock[active_color] = 0
        room.turn_started_at = nil
        room.result = { 'winner' => active_color == 'white' ? 'black' : 'white', 'reason' => 'timeout' }
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
