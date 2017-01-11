require 'digest'

module Chess
  class Game
    # TODO
    # check for resignation
    # handle move + draw, and acceptance
    # states for accepted_draw, etc
    # check log - enforce 50-rule draw

    public

    def get_computer_move
      depth = 2
      mv = AI.find_move board, depth
    end

    def get_player_move
      gets.strip
    end

    def get_move
      get_computer_move # FIXME add human
    end

    def play single_step = true
      puts "#{status}#{" - winner #{winner}" if :checkmate == status}"
      puts
      board.display
      loop do
        # TODO check log for draw offer, consider accepting
        (puts "Game ended in #{status}" ; break) unless :in_progress == status
        print "#{board.to_play} playing#{" - move #{board.halfmove_number}" unless 1 == board.halfmove_number}#{' - check' if board.check?}"
        # puts "- #{mvs.length} moves available"
        @winner, @loser = board.next_to_play, board.to_play if board.checkmate?
        mv = get_move
        # mv = mvs.sample
        puts "- #{mv.description}"
        move mv
        puts "\n#{board.to_play} to play#{' - check' if board.check?}"
        board.display
        # puts board.distinct_state
        gets if single_step
      end
    end

    def move mv
      # Check if enough pieces are left to mate, eventually this is the player's job
      board.move mv
    end

    # Returns true if the *current* state has happened two or more times before
    # If you do not call for draw when at the repeated position, you lose the ability
    # FIXME Determine if you may cause the position for the third time and call for draw, or if only the opponent can
    def threefold_repetition
      count = 0
      current_state = board.states.last
      board.states.reverse.each {|state|
        next unless current_state == state
        count += 1
        return true if 3 == count
      }
      false
    end


    def status
      if threefold_repetition
        :draw
      else
        board.status
      end
    end

    def winner ; board.winner end
    def check? ; board.check? end
    def display ; board.display end
    def history ; board.history end

    def inspect ; "<#{self.class.name}:#{'0x%014x' % (object_id << 1)} halfmove #{board.halfmove_number} - #{status} - #{board.inspect}>" end

    def journal ; history.each_with_index.map {|h,i| "Move #{i + 1} - #{h.description}" } end

    # For UI
    def create_move_from_pgn pgn
      # find piece
      # create move
    end

    attr_reader :board
    def initialize board = nil
      @board = board || Board.new(layout: :default_8x8)
    end
  end
end
