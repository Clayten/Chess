require 'digest'

module Chess
  class Game
    # TODO
    # check for resignation
    # handle move + draw, and acceptance
    # states for accepted_draw, etc
    # check log - enforce 50-rule draw

    public

    def rate_move mv
      base = 0
      base += 100 if mv.captured_type
      base
    end

    def rate_moves mvs
      mvs.sort_by {|mv| rate_move mv }.reverse
    end

    def play
      puts "#{status}#{" - winner #{winner}" if :checkmate == status}"
      puts
      board.display
      loop do
        # TODO check log for draw offer, consider accepting
        break unless :in_progress == board.status
        puts "#{board.to_play} playing #{" - move #{board.halfmove_number}" unless 1 == board.halfmove_number}#{' - check' if board.check?}"
        mvs = board.moves
        puts "- #{mvs.length} moves available"
        @winner, @loser = board.next_to_play, board.to_play if board.checkmate?
        mv = rate_moves(mvs.shuffle).first
        puts "- Moving #{mv.type} from #{mv.src} to #{mv.dest}#{" capturing #{mv.captured_type}" if mv.captured_type}\n\n"
        puts "#{board.to_play} to play#{' - check' if board.check?}"
        move mv
        board.display
        gets
        clr = :white == clr ? :black : :white
      end
    end

    def move mv
      # TODO Check if it's a pawn move, or a capture, then reset the 50-move draw clock
      # Check if enough pieces are left to mate, eventually this is the player's job
      board.move mv
    end

    def status ; board.status end
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
    def initialize
      @board = Board.new(layout: :default_8x8)
    end
  end
end
