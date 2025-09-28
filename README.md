# checkmate.rb

A chess game where you play White against a Ruby-built AI opponent, served by a small Sinatra app with a from-scratch chess engine — no external chess library.

![checkmate.rb board with debug mode enabled](docs/screenshot.png)

![AI debug panel showing search depth, nodes, and candidate moves](docs/ai-debug-panel.png)

## Features

- Fully legal move generation: check, checkmate, stalemate, castling, en passant, and promotion
- FEN-based game state, kept server-side in the session
- AI opponent using negamax search with alpha-beta pruning and a material + piece-square-table evaluation
- Adjustable AI strength (illustrative Elo tiers, tuned via search depth and move randomness)
- Click-to-move and drag-and-drop board, with a choice of piece sets

## Requirements

- Ruby 3.4.10 (see `Gemfile`)
- Bundler

## Setup

```sh
bundle install
```

## Run

```sh
bundle exec rackup
```

Then open `http://localhost:9292`.

## Test

```sh
bundle exec rake
```

## Project structure

```
app.rb              Sinatra app / HTTP API
lib/chess/          Board, move generation, and game rules
lib/ai/             Search-based AI opponent
public/             Frontend (HTML/CSS/JS) and piece sets
spec/                RSpec tests
```

## License

[MIT](LICENSE)
