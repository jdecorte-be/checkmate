// Minimal, dependency-free chess board renderer.
//
// This is a pure view: it never decides whether a move is legal. Clicking
// or dragging a piece to a square calls `onMove({ from, to })` and then
// snaps back to the current position. It is the caller's job (talking to
// the Ruby backend) to validate the move and, if it's legal, call
// `board.move(from, to, opts)` to actually commit and animate it.

const FILES = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];

const FEN_PIECE_MAP = {
  p: 'bP', n: 'bN', b: 'bB', r: 'bR', q: 'bQ', k: 'bK',
  P: 'wP', N: 'wN', B: 'wB', R: 'wR', Q: 'wQ', K: 'wK',
};

const DRAG_THRESHOLD = 4; // px of pointer movement before a click becomes a drag

// Parses only the piece-placement field of a FEN string into { square: pieceCode }
export function fenToPosition(fenBoard) {
  const position = {};
  const ranks = ['8', '7', '6', '5', '4', '3', '2', '1'];
  const rows = fenBoard.split(' ')[0].split('/');
  rows.forEach((row, rankIndex) => {
    let file = 0;
    for (const char of row) {
      if (/\d/.test(char)) {
        file += Number(char);
      } else {
        const square = FILES[file] + ranks[rankIndex];
        position[square] = FEN_PIECE_MAP[char];
        file += 1;
      }
    }
  });
  return position;
}

function coordsFor(square, orientation) {
  const file = square.charCodeAt(0) - 97;
  const rank = Number(square[1]);
  return orientation === 'white'
    ? { col: file, row: 8 - rank }
    : { col: 7 - file, row: rank - 1 };
}

function squareAt(col, row, orientation) {
  const { file, rank } = orientation === 'white'
    ? { file: col, rank: 8 - row }
    : { file: 7 - col, rank: row + 1 };
  return FILES[file] + rank;
}

export default class ChessBoard {
  constructor(el, options = {}) {
    this.el = el;
    this.orientation = options.orientation || 'white';
    this.pieceSet = options.pieceSet || 'cburnett';
    this.piecesRoot = options.piecesRoot || '/pieces';
    this.onMove = options.onMove || (() => {});
    this.getDests = options.getDests || null; // (square) => string[] | undefined
    this.viewOnly = !!options.viewOnly;

    this.position = {};
    this.squareEls = {};
    this.pieceEls = {};
    this.selected = null;
    this._drag = null;

    this.el.classList.add('board');
    this._createSquares();
    if (options.position) this.setPosition(options.position);
  }

  // -- public API -----------------------------------------------------

  // Hard reset with no animation (initial load, or forced resync after
  // a desync/illegal-move rejection from the backend).
  setPosition(position) {
    this.position = typeof position === 'string' ? fenToPosition(position) : { ...position };
    Object.values(this.pieceEls).forEach(el => el.remove());
    this.pieceEls = {};
    Object.entries(this.position).forEach(([square, code]) => {
      this.pieceEls[square] = this._createPieceEl(square, code);
    });
    this.clearSelection();
  }

  // Animated, incremental move: slides the piece at `from` to `to`.
  // opts.promotion  - piece code to swap to on arrival, e.g. 'wQ'
  // opts.capture    - square to remove a piece from (defaults to `to`;
  //                    pass the pawn's square for en passant)
  // opts.secondary  - { from, to } for the rook in a castling move
  move(from, to, opts = {}) {
    const captureSquare = opts.capture || to;
    if (captureSquare !== from) this._removePiece(captureSquare);

    const pieceEl = this.pieceEls[from];
    if (!pieceEl) {
      console.warn(`board.move: no piece on ${from}`);
      return;
    }
    delete this.pieceEls[from];
    delete this.position[from];
    this.pieceEls[to] = pieceEl;
    this.position[to] = opts.promotion || pieceEl.dataset.piece;
    pieceEl.dataset.square = to;
    this._positionPieceEl(pieceEl, to);

    if (opts.promotion) {
      pieceEl.dataset.piece = opts.promotion;
      window.setTimeout(() => this._applyPieceImage(pieceEl), 120);
    }

    if (opts.secondary) {
      this.move(opts.secondary.from, opts.secondary.to);
    }

    this.setLastMove(from, to);
  }

  setViewOnly(viewOnly) {
    this.viewOnly = viewOnly;
    if (viewOnly) this.clearSelection();
  }

  setOrientation(color) {
    this.orientation = color;
    Object.entries(this.squareEls).forEach(([square, el]) => this._positionEl(el, square));
    Object.entries(this.pieceEls).forEach(([square, el]) => this._positionEl(el, square));
    this._renderCoordinates();
  }

  flip() {
    this.setOrientation(this.orientation === 'white' ? 'black' : 'white');
  }

  setPieceSet(name) {
    this.pieceSet = name;
    Object.values(this.pieceEls).forEach(el => this._applyPieceImage(el));
  }

  setLastMove(from, to) {
    Object.values(this.squareEls).forEach(sq => {
      sq.classList.remove('last-move-from', 'last-move-to');
    });
    if (from) this.squareEls[from]?.classList.add('last-move-from');
    if (to) this.squareEls[to]?.classList.add('last-move-to');
  }

  setCheck(square) {
    Object.values(this.squareEls).forEach(sq => sq.classList.remove('in-check'));
    if (square) this.squareEls[square]?.classList.add('in-check');
  }

  showMoveDests(squares = []) {
    Object.values(this.squareEls).forEach(sq => sq.classList.remove('move-dest'));
    squares.forEach(square => this.squareEls[square]?.classList.add('move-dest'));
  }

  clearSelection() {
    if (this.selected) this.squareEls[this.selected]?.classList.remove('selected');
    this.selected = null;
    this.showMoveDests([]);
  }

  // -- square/piece DOM ------------------------------------------------

  _createSquares() {
    FILES.forEach(file => {
      for (let rank = 1; rank <= 8; rank += 1) {
        const square = file + rank;
        const isLight = (FILES.indexOf(file) + rank) % 2 === 1;
        const div = document.createElement('div');
        div.className = `square ${isLight ? 'light' : 'dark'}`;
        div.dataset.square = square;
        this._positionEl(div, square);
        // Only reachable by clicks when the square has no piece on top of it
        // (pieces are siblings rendered above squares, not children of them).
        div.addEventListener('click', () => this._handleSquareClick(square));
        this.el.appendChild(div);
        this.squareEls[square] = div;
      }
    });
    this._renderCoordinates();
  }

  // Labels are children of the edge squares so they ride along automatically
  // with the squares' own flip transition instead of needing their own.
  _renderCoordinates() {
    Object.values(this.squareEls).forEach(el => {
      el.querySelectorAll('.coord').forEach(label => label.remove());
    });

    const bottomRank = this.orientation === 'white' ? 1 : 8;
    FILES.forEach(file => {
      const label = document.createElement('span');
      label.className = 'coord coord-file';
      label.textContent = file;
      this.squareEls[file + bottomRank].appendChild(label);
    });

    const leftFile = this.orientation === 'white' ? 'a' : 'h';
    for (let rank = 1; rank <= 8; rank += 1) {
      const label = document.createElement('span');
      label.className = 'coord coord-rank';
      label.textContent = rank;
      this.squareEls[leftFile + rank].appendChild(label);
    }
  }

  _createPieceEl(square, code) {
    const el = document.createElement('div');
    el.className = 'piece';
    el.dataset.square = square;
    el.dataset.piece = code;
    this._applyPieceImage(el);
    this._positionEl(el, square);
    el.addEventListener('pointerdown', e => this._onPointerDown(e, el));
    this.el.appendChild(el);
    return el;
  }

  _applyPieceImage(el) {
    el.style.backgroundImage = `url('${this.piecesRoot}/${this.pieceSet}/${el.dataset.piece}.svg')`;
  }

  _positionEl(el, square) {
    const { col, row } = coordsFor(square, this.orientation);
    el.style.left = `${col * 12.5}%`;
    el.style.top = `${row * 12.5}%`;
  }

  _positionPieceEl(el, square) {
    this._positionEl(el, square);
  }

  _removePiece(square) {
    const el = this.pieceEls[square];
    if (!el) return;
    delete this.pieceEls[square];
    delete this.position[square];
    el.classList.add('fading');
    el.addEventListener('transitionend', () => el.remove(), { once: true });
    window.setTimeout(() => el.remove(), 300); // fallback if transitionend never fires
  }

  // -- click-to-move -----------------------------------------------------

  _handleSquareClick(square) {
    if (this.viewOnly) return;
    if (this.selected === square) {
      this.clearSelection();
      return;
    }
    if (this.selected) {
      const from = this.selected;
      this.clearSelection();
      this.onMove({ from, to: square });
      return;
    }
    if (this.position[square]) {
      this.selected = square;
      this.squareEls[square].classList.add('selected');
      if (this.getDests) this.showMoveDests(this.getDests(square) || []);
    }
  }

  // -- drag-and-drop -------------------------------------------------

  _onPointerDown(e, el) {
    if (this.viewOnly || (e.button !== undefined && e.button !== 0)) return;
    const square = el.dataset.square;

    // A piece already selected, and this pointerdown landed on a *different*
    // square's piece (e.g. an enemy piece to capture) - complete the move
    // instead of starting a fresh drag on that piece.
    if (this.selected && this.selected !== square) {
      const from = this.selected;
      this.clearSelection();
      this.onMove({ from, to: square });
      return;
    }

    el.setPointerCapture(e.pointerId);
    this._drag = {
      square,
      el,
      pointerId: e.pointerId,
      startX: e.clientX,
      startY: e.clientY,
      dragging: false,
    };
    el.addEventListener('pointermove', this._onPointerMove);
    el.addEventListener('pointerup', this._onPointerUp);
    el.addEventListener('pointercancel', this._onPointerUp);
  }

  _onPointerMove = e => {
    const drag = this._drag;
    if (!drag || e.pointerId !== drag.pointerId) return;
    const dx = e.clientX - drag.startX;
    const dy = e.clientY - drag.startY;

    if (!drag.dragging) {
      if (Math.abs(dx) < DRAG_THRESHOLD && Math.abs(dy) < DRAG_THRESHOLD) return;
      drag.dragging = true;
      drag.boardRect = this.el.getBoundingClientRect();
      drag.el.classList.add('dragging');
      this.selected = drag.square;
      this.squareEls[drag.square]?.classList.add('selected');
      if (this.getDests) this.showMoveDests(this.getDests(drag.square) || []);
    }

    const size = drag.boardRect.width / 8;
    const x = e.clientX - drag.boardRect.left - size / 2;
    const y = e.clientY - drag.boardRect.top - size / 2;
    drag.el.style.left = `${x}px`;
    drag.el.style.top = `${y}px`;
  };

  _onPointerUp = e => {
    const drag = this._drag;
    if (!drag || e.pointerId !== drag.pointerId) return;
    drag.el.releasePointerCapture(drag.pointerId);
    drag.el.removeEventListener('pointermove', this._onPointerMove);
    drag.el.removeEventListener('pointerup', this._onPointerUp);
    drag.el.removeEventListener('pointercancel', this._onPointerUp);
    drag.el.classList.remove('dragging');

    if (drag.dragging) {
      const size = drag.boardRect.width / 8;
      const col = Math.min(7, Math.max(0, Math.floor((e.clientX - drag.boardRect.left) / size)));
      const row = Math.min(7, Math.max(0, Math.floor((e.clientY - drag.boardRect.top) / size)));
      const target = squareAt(col, row, this.orientation);
      this.clearSelection();
      // Snap back to the true (unconfirmed) position; caller commits via move().
      this._positionEl(drag.el, drag.square);
      if (target && target !== drag.square) {
        this.onMove({ from: drag.square, to: target });
      }
    } else {
      this._handleSquareClick(drag.square);
    }

    this._drag = null;
  };
}
