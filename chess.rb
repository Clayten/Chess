#!/usr/bin/env ruby

require 'pry'

$LOAD_PATH << File.expand_path('.')

require 'board'
require 'piece'
require 'action'
require 'game'

# For now, also just reload them each time
load 'board.rb'
load 'piece.rb'
load 'action.rb'
load 'game.rb'

module Chess

  def self.cli
    binding.pry
  end
end

Chess.cli if __FILE__ == $0

# Notes
#
# ###
# A piece projects check even if moving to capture would expose its own king to attack # http://www.chessvariants.com/d.chess/faq.html
# ■□♜
# ♚♟♖
# ■□♔
# White cannot move its pawn, despite the fact that the checking rook is pinned.
#
# ###
#
# We need the last-time a piece moved (for en-passant)
# We need the number of times moved (for en-passant)
# We need a boolean .moved? (for castling)
