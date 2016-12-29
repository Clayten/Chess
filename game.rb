require 'digest'

module Chess
  class Game
    # TODO
    # get a Move object
    # check for resignation
    # check for checkmate
    # check log - enforce 50-rule draw

    public

    def play
      puts "#{status}#{" - winner #{winner}" if :checkmate == status}"
      puts
      board.display
      loop do
        break unless :in_progress == status
        puts "#{board.to_play} to play#{" - move #{board.move_number}" unless 1 == board.move_number}#{' - check' if board.check?}"
        mvs = board.moves
        puts "\t#{mvs.length} moves available"
        if mvs.empty?
          if board.check?
            @status = :checkmate
            @winner, @loser = board.next_to_play, board.to_play
          else
            @status = :stalement
          end
          puts status
          return status
        end
        mv = mvs.sample
        pc, src, dst = mv
        capture = dst[2]
        dest = dst.first(2)
        src2, dest2 = dst[3..4], dst[5..6]
        # Check if it's a pawn move, or a capture, then reset the 50-move draw clock
        puts "\tMoving #{pc} from #{src} to #{dest}#{" capturing #{capture}" if capture}\n\n"
        board.move *src, *dest, *src2, *dest2
        puts "#{board.to_play} to play#{' - check' if board.check?}"
        board.display
        gets
        print `clear`
        clr = :white == clr ? :black : :white
      end
    end

    def check? ; board.check? end

    def display ; board.display end

    def inspect ; "<#{self.class.name}:#{'0x%014x' % (object_id << 1)} turn #{board.move_number} - #{status} - #{board.inspect}>" end

    attr_reader :board, :status, :winner, :loser
    def initialize board = nil
      @board = Board.new.setup
      @status = :in_progress
      @draw_turn = board.move_number + 50
    end
  end
end
