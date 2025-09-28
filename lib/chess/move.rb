module Chess
  # rook_from/rook_to: the rook's own move, alongside the king's from/to on Move
  Castle = Struct.new(:rook_from, :rook_to, keyword_init: true)

  # promotion: lowercase piece letter ('q', 'r', 'b', 'n'), or nil
  # en_passant_capture: square of the pawn actually removed, when it isn't `to`
  # castle: a Castle, or nil
  Move = Struct.new(:from, :to, :promotion, :en_passant_capture, :castle, keyword_init: true)
end
