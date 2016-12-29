module Chess
  class Board

    attr_reader :states

    # Hash state, store, check for triplicates - draw
    def states ; @states ||= [] end

    def distinct_state ; "<#{self.class.name} #{xsize}x#{ysize} #{pieces.map {|(x,y),pc| "(#{pc.color} #{pc.type}-#{x},#{y}-#{pc.moved?})" }.join(', ')}#{" - cap #{captures.map {|pc| "#{pc.type}" }.join(',')}" unless captures.empty?}>" end

    def state_hash ; Digest::SHA256.hexdigest distinct_state end

    def try_move sx, sy, dx, dy
      dup.force_move(sx,sy,dx,dy)
    end

    # [int, int] or [char, int]
    def parse x, y
      x = x.to_i(10 + xsize) - 10 unless x.is_a? Integer # by default, base 18 ('a' -> 'h') - 10 == 0->7
      raise "x: #{x} out of bounds" if x < 1 || x > xsize
      raise "y: #{y} out of bounds" if y < 1 || y > ysize
      [x, y]
    end

    def piece_at x, y
      pieces[parse x, y]
    end

    def location_of piece
      return :captured if captures.include? piece
      loc, _ = pieces.find {|loc, pc| pc == piece }
      loc
    end

    def white_square ; "\u25a0" end
    def black_square ; "\u25a1" end
    def square color ; color == :white ? white_square : black_square end

    def color_at x, y
      x, y = parse x, y
      (((x % 2) + (y % 2)) % 2).zero? ? :white : :black
    end

    def render
      1.upto(ysize).map {|y|
        1.upto(xsize).map {|x|
          piece_at(x,y) || square(color_at(x,y))
        }.join
      }.join("\n")
    end
    def display
      puts render
    end

    attr_reader :pieces

    public

    def next_to_play ; Piece.other_color to_play end

    def to_play ; Piece.colors[move_number % 2] end

    def check?
      moves(next_to_play, true).each {|_,_,(_,_,type)|
        return true if type && :king == type
      }
      false
    end

    # These methods return a list of legal moves of a given type, from a location, for a color

    # Just checks for the king's ability to castle
    def castling x, y, color
      # Has to make sure king doesn't start on or cross a square in check (like en-passant, but disallowed)
      # All pieces between king and rook must be clear
      results = []
      return results if caller.any? {|c| c =~ /castling/ } # avoid recursion in checking for check across intermediate squares
      king = piece_at x, y
      raise "Not a king" unless :king == king.type
      return results if king.moved?
      return results unless 8 == xsize && 8 == ysize # So far, we only castle on regulation boards
      opponent_moves = moves next_to_play, true
      locations_in_check = opponent_moves.map {|_,_,(x,y,_)| [x,y] }.sort.uniq
      return results if locations_in_check.include? [x, y]
      [1, 8].each {|rx|
        rook = piece_at rx, y
        next if !rook || rook.moved?
        intermediate_squares = (([rx, x].min + 1)...[rx, x].max).to_a
        next if intermediate_squares.any? {|ix|
          next true if piece_at ix, y
          next true if locations_in_check.include? [ix, y]
        }
         dx = 8 == rx ? 7 : 3 # destination file for king
        rdx = 8 == rx ? 6 : 4 # for rook
        results << [dx, y, nil, rx, y, rdx, y] # TODO - Move.new(:castle, [x,y],[dx,y],nil,[rx,y],[rdx,y])
      }
      results
    end

    # Outward along cardinal (N/S, E/W) lines - ranks and files
    def cardinal_lines x, y, color
      x, y = parse x, y
      results = []
      xrays = [(x - 1).downto(1), (x + 1).upto(xsize)].map(&:to_a).map {|xs| xs.zip([y] * xs.length) }
      yrays = [(y - 1).downto(1), (y + 1).upto(ysize)].map(&:to_a).map {|ys| ([x] *ys.length).zip ys }
      rays = xrays + yrays
      rays.each {|ray|
        ray.each {|tx,ty|
          if pc = piece_at(tx, ty)
            results << [tx, ty, pc.type] unless pc.color == color
            break
          end
          results << [tx, ty]
        }
      }
      results 
    end

    # Outward along diagonal lines
    def diagonal_lines x, y, color
      x, y = parse x, y
      results = []
      tdrays = [(x - 1).downto(1).to_a.zip((y - 1).downto(1).to_a), (x + 1).upto(xsize).to_a.zip((y + 1).upto(ysize).to_a)]
      burays = [(x - 1).downto(1).to_a.zip((y + 1).upto(ysize).to_a), (x + 1).upto(xsize).to_a.zip((y - 1).downto(1).to_a)]
      rays = tdrays + burays
      rays.each {|ray|
        ray.each {|tx,ty|
          next unless tx && ty
          if pc = piece_at(tx, ty)
            results << [tx, ty, pc.type] unless pc.color == color
            break
          end
          results << [tx, ty]
        }
      }
      results
    end

    # Squares surrounding
    def adjacent_squares x, y, color
      x, y = parse x, y
      results = []
      (x - 1).upto(x + 1).each {|tx|
        (y - 1).upto(y + 1).each {|ty|
          next if x == tx && y == ty
          next if tx < 1 || tx > xsize || ty < 1 || ty > ysize
          if pc = piece_at(tx, ty)
            results << [tx, ty, pc.type] unless pc.color == color
            next
          end
          results << [tx, ty]
        }
      }
      results
    end

    # Two and one, or one and two, away in all directions
    def knight_moves x, y, color
      x, y = parse x, y
      results = []
      offsets = [[-1, -2], [-2, -1], [1, -2], [2, -1], [-1, 2], [-2, 1], [1, 2], [2, 1]]
      offsets.each {|ox,oy|
        tx, ty = (x + ox), (y + oy)
        next if tx < 1 || tx > xsize || ty < 1 || ty > ysize
        if pc = piece_at(tx, ty)
          results << [tx, ty, pc.type] unless pc.color == color
          next
        end
        results << [tx, ty]
      }
      results
    end

    # Foward, attacking to the sides, and capturing en-passant
    # Here color is more functional, white advances towards black, etc
    def pawn_moves x, y, color
      x, y = parse x, y
      results = []
      offset = :white == color ? -1 : 1 # which direction are we checking?
      # capturing
      (x - 1).upto(x + 1).each {|tx|
        ty = y + offset
        next if tx < 1 || tx > xsize || ty < 1 || ty > ysize
        if pc = piece_at(tx, ty)
          results << [tx, ty, pc.type] unless pc.color == color
          next
        end
      }
      # just moving
      steps = !piece_at(x,y).last_move ? 2 : 1
      y1, y2 = [(y + offset), (y + offset * steps)].sort
      y1.upto(y2).each {|ty|
        next if x < 1 || x > xsize || ty < 1 || ty > ysize
        next if piece_at x, ty
        results << [x, ty]
      }
      # en passant
      [-1, 1].each {|ox|
        next unless (:white == color ? 4 : ysize - 3) == y # Check the attacker is on the fifth rank
        tx = x + ox
        next if tx < 1 || tx > xsize
        next unless pc = piece_at(tx, y)
        next unless :pawn == pc.type
        next unless 1 == pc.number_of_moves # We can only capture en-passant if it's the enemy's first move (If they're on their fourth rank, they did it as a double move)
        next unless move_number == pc.last_move # We can only capture en-passant directly after the enemy moves
        results << [tx, (y + offset), pc.type] # we capture in one location but move to another
      }
      results
    end

    # TODO break out list of possible squares to move into, to iterate over for legal moves, and to properly display A pawn can't, and THIS pawn can't...

    # Not for normal use, might leave board in illegal condition
    def force_move sx, sy, dx, dy
      # p [:forcing, sx, sy, :to, dx, dy]
      pieces[[dx,dy]] = pieces[[sx,sy]] # BAM, it's done. But it may not be legal
      pieces.delete [sx,sy]
      # NOTE Not incrementing turn #, etc. We can test our position for own-check this way
      self
    end

    # iterates over all pieces, returns all moves
    # :color -> [[:piece_type, [src_x, src_y], [dest_x, dest_y], capture], [...]]
    def moves color = to_play, dont_check_check = false
      mvs = pieces.values.select {|pc|
        pc.color == color
      }.map {|pc|
        mvs = pc.moves.map {|mv|
          [pc.type, pc.location, mv]
        }
        next if mvs.empty?
        mvs
      }.compact.inject(&:+)
      mvs ||= []
      return mvs if dont_check_check
      # Now weed out moves that result in check
      mvs.select {|_,src,(dx, dy, _)| !try_move(*src,dx,dy).check? } # This is recursive, but doesn't consider check next time
    end

    # Process a move, after checking if it is allowed
    def move x1, y1, dx1, dy1, x2 = nil, y2 = nil, dx2 = nil, dy2 = nil
      src_loc, dest_loc = parse(x1,y1), parse(dx1,dy1)
      src, dest = pieces[src_loc], pieces[dest_loc]
      raise "No piece at #{x1},#{y1}" unless src
      raise "It isn't #{src.color}'s turn" unless src.color == to_play
      raise "A #{src.type} can't move from #{x1},#{y1} to #{dx1},#{dy1}" unless src.can_move_to(*dest_loc)
      raise "Move exposes king to check" if try_move(x1,y1,dx1,dy1).check?
      if dest
        raise "Destination occupied by same color" if dest.color == src.color
        raise "Chess does not support regicide" if :king == dest.type
        captures << dest
      end
      pieces[dest_loc] = pieces.delete(src_loc)
      @move_number += 1
      if x2 # secondary piece - during castling only
        raise "Only castling involves moving two pieces" unless :king == src.type
        raise "King has already moved" if src.moved?
        src_loc2, dest_loc2 = [x2, y2], [dx2, dy2]
        raise "Only rooks can castle with kings" unless :rook == pieces[src_loc2].type
        raise "Rook has already moved" if pieces[src_loc2].moved?
        raise "You must end up on the other side of the king" unless dy1 == dy2 && ((dx1 - 1) == dx2 || (dx1 + 1) == dx2)
        pieces[dest_loc2] = pieces.delete src_loc2
        pieces[dest_loc2].moved
      end
      src.moved
      true
    end

    def add_piece x, y, color, type
      # p [:add_piece, x, y, color, type]
      x, y = parse x, y
      raise "There's already a #{piece_at} at #{x},#{y}!" if piece_at x, y
      pieces[[x,y]] = Piece.create color, type, self
    end

    def setup color = Piece.colors.first
      @move_number = 1
      @pieces.clear
      @captures.clear

      first, second = Piece.colors
      primary = color == first # Are we playing as the first player
      first, second = second, first unless primary # Always set the board up for us at the bottom

      first_front_row = second_front_row = [:pawn] * xsize
      first_back_row  = second_back_row  = %w(rook knight bishop queen king bishop knight rook).map &:to_sym
      (first_front_row.reverse! ; first_back_row.reverse!) unless primary # Maintain queen on own color

      1.upto(xsize) {|x| add_piece x,          1 , first,   first_back_row[ x - 1] # row layouts at 0..(n-1), not 1..n
                         add_piece x,          2 , first,   first_front_row[x - 1]
                         add_piece x, (ysize - 1), second, second_front_row[x - 1]
                         add_piece x,  ysize     , second, second_back_row[ x - 1]
      }
      self
    end

    def inspect
      "<#{self.class.name}:#{'0x%014x' % (object_id << 1)} #{xsize}x#{ysize} - " +
      "#{pieces.length + captures.length} pieces - #{captures.length} captured>"
    end

    def mutate
      pcs, caps = pieces.dup, captures.dup
      @pieces, @captures = {}, []
      pcs.each  {|k,v| v = v.dup ; pieces[k]  = v ; v.board = self }
      caps.each {|  v| v = v.dup ; captures  << v ; v.board = self }
      self
    end

    def dup
      super.mutate
    end

    attr_reader :xsize, :ysize, :captures, :move_number
    def initialize xsize = 8, ysize = 8
      @xsize, @ysize = xsize, ysize
      @pieces = {}
      @captures = []
      @move_number = 1
    end
  end
end
