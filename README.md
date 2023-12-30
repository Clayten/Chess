# Chess - Tools for loading and analyzing chess games.

## About

Not primarily to play chess with, but it is usable for two players. The AI is unworkably slow and was only added because it's almost free at a point.

The main goal was producing heatmaps - "Where did the queens spend time?", and force diagrams - "What squares were under attack the most/least?" and gameplay maps - moves plotted out on a subset of the board, to follow the larger game move by move. 

## Usage

Start a new game
```
chess = Chess::Game.new
c.players[:white] = :player
# Or, leave both players as computer and it will play itself (slowly)
chess.play
```

```
chess = Chess::Game.from_fen(FEN_FILENAME)
```

## License

AGPL2
