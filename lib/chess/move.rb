module Chess
  # promotion: lowercase piece letter ('q', 'r', 'b', 'n'), or nil
  # en_passant_capture: square of the pawn actually removed, when it isn't `to`
  # castle: { rook_from:, rook_to: }, or nil
  Move = Struct.new(:from, :to, :promotion, :en_passant_capture, :castle, keyword_init: true)
end
