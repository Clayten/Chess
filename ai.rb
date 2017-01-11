module Chess
  class AI
    # The final static evaluator
    def self.rate_position board
      # p [:rating, board.to_play, board.transcript]
      # board.display
      values = {  king: 25, # This value isn't required to keep it alive - you simply can't choose to move into check
                 queen: 100,
                  rook: 45,
                bishop: 40,
                knight: 30,
                  pawn: 10}

      # Basic strength from pieces
        own_piece_value =   board.own_pieces.map {|pc| values[pc.type] }.inject(&:+)
      enemy_piece_value = board.enemy_pieces.map {|pc| values[pc.type] }.inject(&:+)
      material_score = own_piece_value - enemy_piece_value

      # Options are good - counts useless moves too though
        own_moves = board.moves
      enemy_moves = board.moves board.next_to_play
      moves_score = (own_moves.length - enemy_moves.length) * 5

      # The enemy's threats toward the current player
      enemy_threat_count_score = enemy_threat_score = enemy_reinforcement_score = 0
      own_threatened_squares = board.threatened_squares
      own_threatened_squares.each {|x,y|
        pc = board.at x, y
        enemy_threat_count_score += 3
        next unless pc
        if board.to_play == pc.color
          enemy_threat_score += v = values[pc.type] * 0.3 # threatened
          # p [:friendly, pc.type, :threated_at, [x,y], :score, v]
        else
          enemy_reinforcement_score += v = values[pc.type] * 0.2 # reinforced
          # p [:enemy, pc.type, :reinforced_at, [x,y], :score, v]
        end
      }

      # The current player's threats and self-reinforcement
      own_threat_count_score = own_threat_score = own_reinforcement_score = 0
      enemy_threatened_squares = board.threatened_squares board.next_to_play
      enemy_threatened_squares.each {|x,y|
        pc = board.at x, y
        own_threat_count_score += 3
        next unless pc
        if board.to_play != pc.color
          own_threat_score += v = values[pc.type] * 0.3 # threatened
          # p [:enemy, pc.type, :threated_at, [x,y], :score, v]
        else
          own_reinforcement_score += v = values[pc.type] * 0.2 # reinforced
          # p [:friendly, pc.type, :reinforced_at, [x,y], :score, v]
        end
      }

      status_modifier = case board.status
      when :in_progress ; 0
      when :draw        ; 0
      when :stalemate   ; 0
      when :checkmate   ; (board.to_play == board.winner) ? 10_000 : -10_000
      end

      score = material_score + moves_score + status_modifier +
          own_threat_count_score +   own_threat_score +   own_reinforcement_score -
        enemy_threat_count_score - enemy_threat_score - enemy_reinforcement_score

      # p [:total_score, score, :material_score, material_score, :moves_score, moves_score, :checkmate, :status_modifier, status_modifier, :enemy_threat_count_score, enemy_threat_count_score, :enemy_threat_score, enemy_threat_score, :enemy_reinforcement_score, enemy_reinforcement_score, :own_threat_count_score, own_threat_count_score, :own_threat_score, own_threat_score, :own_reinforcement_score, own_reinforcement_score]
      score.to_i
    end

    # if depth zero, we aren't recursing we're just evaluating
    # if depth one, deduct one and try all available moves

    # given a board, return the score of each available move

    # given a board and a move and a depth, return the score of that move either directly or recursively
    def self.score_move board, move, depth
      # p [:scoring, :move, move, :to, :depth, depth]
      depth = depth - 1
      board = board.dup
      board.move move
      rating = if depth.zero?
        score = rate_position board
        # p [:move_score, board.transcript, score]
        score
      else
        moves = board.moves board.to_play, false
        if moves.empty?
          score = rate_position board
        else
          scores = moves.map {|mv| score_move board, mv, depth }
          # p [:move_scores, board.transcript, scores, :max, scores.max]
          scores.max
        end
      end
      -rating
    end

    # given a board, return the best move available
    def self.find_move board, depth = 1
      rated_moves = board.moves(board.to_play, false).map {|move| rating = score_move board, move, depth ; [move, rating] }
      best_rating = rated_moves.map {|mv, rating| rating }.max

      # p [:sorted_moves, rated_moves.sort_by {|_,r| r }]

      best_moves = rated_moves.select {|mv, rating| rating == best_rating }
      best_moves.sample.first
    end
  end

end
