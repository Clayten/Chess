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
      print "Enter move: "
      txt = gets.strip
      board.create_pgn_move txt
    rescue StandardError => e
      p [:rescued, e, e.backtrace]
      retry
    end

    def get_move
      :computer == players[board.to_play] ? get_computer_move : get_player_move
    end

    def play single_step = true
      puts "#{status}#{" - winner #{winner}" if :checkmate == status}"
      puts
      board.display
      loop do
        # TODO check log for draw offer, consider accepting
        (puts "Game ended in #{status}" ; break) unless :in_progress == status
        puts "#{board.to_play} playing#{" - move #{board.halfmove_number}" unless 1 == board.halfmove_number}#{' - check' if board.check?}"
        @winner, @loser = board.next_to_play, board.to_play if board.checkmate?
        mv = get_move
        puts "#{mv} - #{mv.description}"
        move mv
        puts "\n#{board.to_play} to play#{' - in check' if board.check?}"
        board.display
        gets if single_step
      end
    end

    def move mv
      # Check if enough pieces are left to mate, eventually this is the player's job
      board.move mv
    end

    def status
      # TODO Include resignation, etc, which is outside the scope of the board
      board.status
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

    attr_reader :board, :players
    def initialize board = nil
      board = Board.new(layout: :default_8x8) unless board
      board = Board.new(layout: board) unless board.respond_to? :pieces
      @players = {white: :computer, black: :computer}
      @board = board
    end
  end
end
