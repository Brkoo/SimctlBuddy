import Foundation

/// How many terminal columns a string occupies.
///
/// Nearly every glyph this interface draws — the box borders, `●`, `○`, `▶`,
/// `↗`, `…`, `·` — is East Asian *Ambiguous*, which means one column in some
/// terminals and two in others. Counting characters instead of columns makes
/// every row wider than the window on a terminal that draws them wide, and a
/// row wider than the window wraps, pushes the rest of the frame down, and
/// eventually scrolls, leaving pieces of old frames behind.
///
/// So the width of an ambiguous glyph is measured from the terminal at startup
/// and carried here.
public struct DisplayMetrics: Sendable, Equatable {
  /// 1 or 2, measured by `TerminalSession.measureAmbiguousWidth()`.
  public let ambiguousWidth: Int

  public static let narrow = DisplayMetrics(ambiguousWidth: 1)

  public init(ambiguousWidth: Int) {
    self.ambiguousWidth = max(1, min(2, ambiguousWidth))
  }

  public func width(of value: String) -> Int {
    value.reduce(0) { $0 + width(of: $1) }
  }

  public func width(of character: Character) -> Int {
    // A character can be several scalars — a flag, or a base plus combining
    // marks. The base decides, and the marks add nothing.
    character.unicodeScalars.reduce(0) { total, scalar in
      max(total, width(of: scalar))
    }
  }

  public func width(of scalar: Unicode.Scalar) -> Int {
    let value = scalar.value
    if value < 0x80 { return 1 }
    if Self.isZeroWidth(scalar) { return 0 }
    if Self.isWide(value) { return 2 }
    if Self.isAmbiguous(value) { return ambiguousWidth }
    return 1
  }

  /// Truncates to at most `limit` columns, never leaving half of a wide glyph.
  public func truncate(_ value: String, to limit: Int) -> String {
    guard limit > 0 else { return "" }
    guard width(of: value) > limit else { return value }
    var result = ""
    var used = 0
    for character in value {
      let next = width(of: character)
      if used + next > limit { break }
      result.append(character)
      used += next
    }
    return result
  }

  /// Pads with spaces to exactly `width` columns, truncating if it overflows.
  public func pad(_ value: String, to target: Int) -> String {
    let clipped = truncate(value, to: target)
    return clipped + String(repeating: " ", count: max(0, target - width(of: clipped)))
  }

  private static func isZeroWidth(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .nonspacingMark, .enclosingMark, .format: return true
    default: return scalar.value == 0x200B || scalar.value == 0xFE0F
    }
  }

  /// Always two columns: CJK, Hangul, and the emoji blocks.
  private static func isWide(_ value: UInt32) -> Bool {
    (0x1100...0x115F).contains(value)
      || (0x2E80...0x303E).contains(value)
      || (0x3041...0x33FF).contains(value)
      || (0x3400...0x4DBF).contains(value)
      || (0x4E00...0x9FFF).contains(value)
      || (0xA000...0xA4CF).contains(value)
      || (0xAC00...0xD7A3).contains(value)
      || (0xF900...0xFAFF).contains(value)
      || (0xFE30...0xFE6F).contains(value)
      || (0xFF00...0xFF60).contains(value)
      || (0xFFE0...0xFFE6).contains(value)
      || (0x1F300...0x1F64F).contains(value)
      || (0x1F680...0x1F6FF).contains(value)
      || (0x1F7E0...0x1F7EB).contains(value)
      || (0x1F900...0x1F9FF).contains(value)
      || (0x1FA70...0x1FAFF).contains(value)
      || (0x20000...0x3FFFD).contains(value)
  }

  /// One column or two, depending on the terminal. This covers the blocks the
  /// interface draws from: arrows, box drawing, blocks, geometric shapes, and
  /// the handful of Latin-1 symbols in the footer.
  private static func isAmbiguous(_ value: UInt32) -> Bool {
    switch value {
    case 0x00A1, 0x00A4, 0x00A7, 0x00A8, 0x00AA, 0x00AD, 0x00AE,
      0x00B0...0x00B4, 0x00B6...0x00BA, 0x00BC...0x00BF, 0x00C6, 0x00D0,
      0x00D7, 0x00D8, 0x00DE...0x00E1, 0x00E6, 0x00E8...0x00EA,
      0x00EC, 0x00ED, 0x00F0, 0x00F2, 0x00F3, 0x00F7...0x00FA, 0x00FC, 0x00FE:
      return true
    case 0x2010, 0x2013...0x2016, 0x2018, 0x2019, 0x201C, 0x201D,
      0x2020...0x2022, 0x2024...0x2027, 0x2030, 0x2032, 0x2033, 0x2035,
      0x203B, 0x203E, 0x2074, 0x207F, 0x2081...0x2084:
      return true
    case 0x20AC, 0x2103, 0x2105, 0x2109, 0x2113, 0x2116, 0x2121, 0x2122,
      0x2126, 0x212B, 0x2153, 0x2154, 0x215B...0x215E:
      return true
    // Arrows, mathematical operators, box drawing, blocks, geometric shapes,
    // and miscellaneous symbols — where this interface lives.
    case 0x2160...0x216B, 0x2170...0x2179, 0x2189,
      0x2190...0x2199, 0x21B8, 0x21B9, 0x21D2, 0x21D4, 0x21E7,
      0x2200, 0x2202, 0x2203, 0x2207, 0x2208, 0x220B, 0x220F, 0x2211,
      0x2215, 0x221A, 0x221D...0x2220, 0x2223, 0x2225, 0x2227...0x222C,
      0x222E, 0x2234...0x2237, 0x223C, 0x223D, 0x2248, 0x224C, 0x2252,
      0x2260, 0x2261, 0x2264...0x2267, 0x226A, 0x226B, 0x226E, 0x226F,
      0x2282...0x2285, 0x2295, 0x2299, 0x22A5, 0x22BF,
      0x2312, 0x2500...0x254B, 0x2550...0x2573, 0x2580...0x258F,
      0x2592...0x2595, 0x25A0, 0x25A1, 0x25A3...0x25A9, 0x25B2, 0x25B3,
      0x25B6, 0x25B7, 0x25BC, 0x25BD, 0x25C0, 0x25C1, 0x25C6...0x25C8,
      0x25CB, 0x25CE...0x25D1, 0x25E2...0x25E5, 0x25EF,
      0x2605, 0x2606, 0x2609, 0x260E, 0x260F, 0x2614, 0x2615, 0x261C,
      0x261E, 0x2640, 0x2642, 0x2660, 0x2661, 0x2663...0x2665,
      0x2667...0x266A, 0x266C, 0x266D, 0x266F, 0x273D, 0x2776...0x277F:
      return true
    default:
      return false
    }
  }
}
