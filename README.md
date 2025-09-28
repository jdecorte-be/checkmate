# checkmate.rb

[![Test](https://github.com/jdecorte-be/checkmate/actions/workflows/test.yml/badge.svg)](https://github.com/jdecorte-be/checkmate/actions/workflows/test.yml)

A chess game where you play White against a Ruby-built AI opponent, served by a small Sinatra app with a from-scratch chess engine — no external chess library.

![checkmate.rb board with debug mode enabled](docs/screenshot.png)

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

## Debug mode

Check the "Debug mode" box in the UI to see what the AI is thinking after each of its moves: engine strength (Elo), search depth, node count, time spent, and the top-scoring candidate moves (or a note when the AI deliberately blunders, per its Elo tier's blunder rate). Under the hood this sends `debug=1` to `/api/ai_move`, which asks `Ai::Engine#choose_move` for its `:debug` payload instead of just the chosen move.

![AI debug panel showing search depth, nodes, and candidate moves](docs/ai-debug-panel.png)

## Why the engine doesn't search deeper

Each Elo tier in `Ai::Engine::LEVELS` caps search at a modest depth (1-5 plies) within a short time budget (1-6s). A few reasons compound to keep it shallow:

- **Synchronous HTTP request** — `POST /api/ai_move` blocks until the search returns, so search time is directly page-load latency. There's no background job or websocket to search asynchronously, hence the hard per-move time budget and the `SearchTimeout` that aborts a mid-iteration search once the deadline passes.
- **Move generation dominates per-node cost** — the move generator is plain Ruby (array/FEN-based, no bitboards), and it's needed at every node, including quiescence captures. That makes each additional ply expensive in wall-clock time.
- **Deliberate Elo simulation** — lower tiers are shallow on purpose (plus blunder chance and score noise) to emulate weaker play, not just to save time.
- **No transposition table** — iterative deepening re-searches each depth from scratch with no cache of previously-seen positions, so work isn't reused across iterations.
- **Ruby itself** — single-threaded, no compiled hot path, which caps achievable nodes/sec versus a native engine.

To search deeper, the highest-leverage changes would be a transposition table, a bitboard-based move generator, and moving the search off the request thread (background job + polling/websocket) so the time budget isn't tied to HTTP latency.

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
