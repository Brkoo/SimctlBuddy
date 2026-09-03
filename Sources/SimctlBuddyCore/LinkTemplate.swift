import Foundation

/// One `$name` in a deep link, with the default written alongside it if the
/// template supplied one.
public struct LinkParameter: Equatable, Sendable {
  public let name: String
  public let defaultValue: String?

  public init(name: String, defaultValue: String? = nil) {
    self.name = name
    self.defaultValue = defaultValue
  }

  /// `$0`, `$1` — written by position rather than by name.
  public var isPositional: Bool {
    !name.isEmpty && name.allSatisfy(\.isNumber)
  }

  /// What to call it in a prompt.
  public var label: String {
    isPositional ? "Parameter \(name)" : name
  }
}

public enum LinkSegment: Equatable, Sendable {
  case text(String)
  /// `$scheme`, filled in from the app the link is opened on.
  case scheme
  case parameter(LinkParameter)
}

/// A saved deep link, which may be a finished URL or a template.
///
/// `$scheme://automation?staging-slot=$slot=staging5` covers every market's app
/// with one definition: `$scheme` comes from the app being targeted and `$slot`
/// is asked for, starting from `staging5`.
///
/// - `$name` asks for a value, `$name=value` supplies a default
/// - `$0`, `$1` do the same by position
/// - `${name=a&b}` brackets a default that contains delimiters
/// - `$$` is a literal dollar sign
public struct LinkTemplate: Equatable, Sendable {
  public let raw: String
  public let segments: [LinkSegment]

  /// Characters that end an unbracketed default value.
  private static let defaultTerminators = Set("&/?#")

  public init(raw: String, segments: [LinkSegment]) {
    self.raw = raw
    self.segments = segments
  }

  public static func parse(_ raw: String) -> LinkTemplate {
    var segments = [LinkSegment]()
    var text = ""
    var index = raw.startIndex

    func flushText() {
      if !text.isEmpty {
        segments.append(.text(text))
        text = ""
      }
    }

    while index < raw.endIndex {
      let character = raw[index]
      guard character == "$" else {
        text.append(character)
        index = raw.index(after: index)
        continue
      }

      let afterDollar = raw.index(after: index)
      guard afterDollar < raw.endIndex else {
        // A trailing "$" is just a dollar sign.
        text.append(character)
        index = afterDollar
        continue
      }

      switch raw[afterDollar] {
      case "$":
        text.append("$")
        index = raw.index(after: afterDollar)
      case "{":
        let contentStart = raw.index(after: afterDollar)
        guard let closing = raw[contentStart...].firstIndex(of: "}") else {
          // Unterminated, so treat it as literal text rather than guessing.
          text.append(character)
          index = afterDollar
          continue
        }
        flushText()
        segments.append(segment(for: String(raw[contentStart..<closing])))
        index = raw.index(after: closing)
      default:
        var cursor = afterDollar
        while cursor < raw.endIndex, Self.isNameCharacter(raw[cursor]) {
          cursor = raw.index(after: cursor)
        }
        let name = String(raw[afterDollar..<cursor])
        guard !name.isEmpty else {
          text.append(character)
          index = afterDollar
          continue
        }

        var value: String?
        if name != "scheme", cursor < raw.endIndex, raw[cursor] == "=" {
          var valueCursor = raw.index(after: cursor)
          var collected = ""
          while valueCursor < raw.endIndex,
            !Self.defaultTerminators.contains(raw[valueCursor]),
            !raw[valueCursor].isWhitespace
          {
            collected.append(raw[valueCursor])
            valueCursor = raw.index(after: valueCursor)
          }
          value = collected
          cursor = valueCursor
        }

        flushText()
        if name == "scheme" {
          segments.append(.scheme)
        } else {
          segments.append(.parameter(LinkParameter(name: name, defaultValue: value)))
        }
        index = cursor
      }
    }
    flushText()
    return LinkTemplate(raw: raw, segments: segments)
  }

  private static func segment(for content: String) -> LinkSegment {
    guard content != "scheme" else { return .scheme }
    if let equals = content.firstIndex(of: "=") {
      return .parameter(
        LinkParameter(
          name: String(content[content.startIndex..<equals]),
          defaultValue: String(content[content.index(after: equals)...])
        ))
    }
    return .parameter(LinkParameter(name: content))
  }

  private static func isNameCharacter(_ character: Character) -> Bool {
    character.isLetter || character.isNumber || character == "_" || character == "-"
  }

  public var requiresScheme: Bool {
    segments.contains(.scheme)
  }

  /// Parameters in the order they appear, each listed once. A name repeated with
  /// a default in only one place still gets that default.
  public var parameters: [LinkParameter] {
    var seen = [String: Int]()
    var result = [LinkParameter]()
    for case .parameter(let parameter) in segments {
      if let index = seen[parameter.name] {
        if result[index].defaultValue == nil, parameter.defaultValue != nil {
          result[index] = parameter
        }
        continue
      }
      seen[parameter.name] = result.count
      result.append(parameter)
    }
    return result
  }

  public var isTemplate: Bool {
    requiresScheme || !parameters.isEmpty
  }

  /// Parameters still without a value, given what has been collected so far.
  public func unresolvedParameters(given values: [String: String]) -> [LinkParameter] {
    parameters.filter { values[$0.name] == nil && $0.defaultValue == nil }
  }

  public func render(scheme: String? = nil, values: [String: String] = [:]) throws -> String {
    // Defaults come from the deduplicated list, so `$id/detail/$id=9` applies
    // the default to both occurrences rather than only the one that carries it.
    var defaults = [String: String]()
    for parameter in parameters {
      if let value = parameter.defaultValue { defaults[parameter.name] = value }
    }

    var result = ""
    for segment in segments {
      switch segment {
      case .text(let text):
        result += text
      case .scheme:
        guard let scheme, !scheme.isEmpty else { throw SimctlBuddyError.missingLinkScheme }
        result += scheme
      case .parameter(let parameter):
        guard
          let value = values[parameter.name] ?? parameter.defaultValue
            ?? defaults[parameter.name]
        else {
          throw SimctlBuddyError.missingLinkParameter(parameter.name)
        }
        result += value
      }
    }
    return result
  }

  /// Checks the shape of a template by rendering it with stand-in values, so a
  /// typo is caught when the link is saved rather than when it is opened.
  public func validate() throws {
    var values = [String: String]()
    for parameter in parameters { values[parameter.name] = "x" }
    let rendered = try render(scheme: requiresScheme ? "scheme" : nil, values: values)
    guard SimctlClient.isValidDeepLink(rendered) else {
      throw SimctlBuddyError.invalidURL(raw)
    }
  }

  /// A parameter may stand in for the scheme too — `$market://x` asks for it
  /// like any other value. `$scheme` is the special case that reads it from a
  /// saved app instead.
  ///
  /// A scheme is what `openurl` will see before the `://`, so hold it to the
  /// same rule.
  public static func isValidScheme(_ value: String) -> Bool {
    guard let first = value.first, first.isLetter else { return false }
    return value.allSatisfy { $0.isLetter || $0.isNumber || "+-.".contains($0) }
  }
}

/// One piece of a link shown while its parameters are being filled in.
public struct LinkPreviewPart: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    /// Literal text from the template.
    case text
    /// A parameter that already has a value, or a default that will be used.
    case filled
    /// The parameter being typed right now.
    case current
    /// A parameter still to be asked for.
    case pending
  }

  public let text: String
  public let kind: Kind

  public init(text: String, kind: Kind) {
    self.text = text
    self.kind = kind
  }
}

extension LinkTemplate {
  /// The whole link as it stands, for showing above the field while a value is
  /// being typed.
  ///
  /// Unlike `render`, nothing here throws: the point is to show a link that is
  /// still incomplete, with what is missing marked rather than refused. The
  /// parameter in hand is marked separately so it can be highlighted, which is
  /// what tells someone where the value they are typing will land.
  public func preview(
    scheme: String? = nil,
    values: [String: String] = [:],
    current: String? = nil,
    currentValue: String = ""
  ) -> [LinkPreviewPart] {
    var defaults = [String: String]()
    for parameter in parameters {
      if let value = parameter.defaultValue { defaults[parameter.name] = value }
    }

    var parts = [LinkPreviewPart]()
    func append(_ text: String, _ kind: LinkPreviewPart.Kind) {
      guard !text.isEmpty else { return }
      // Runs of the same kind read as one piece, which keeps the highlighting
      // from fragmenting across adjacent literal segments.
      if let last = parts.last, last.kind == kind {
        parts[parts.count - 1] = LinkPreviewPart(text: last.text + text, kind: kind)
      } else {
        parts.append(LinkPreviewPart(text: text, kind: kind))
      }
    }

    for segment in segments {
      switch segment {
      case .text(let text):
        append(text, .text)
      case .scheme:
        if let scheme, !scheme.isEmpty {
          append(scheme, .filled)
        } else {
          append("$scheme", .pending)
        }
      case .parameter(let parameter):
        if parameter.name == current {
          // Echoing what is being typed is the whole point: the link updates
          // under the cursor as the value is entered.
          append(currentValue.isEmpty ? "$\(parameter.name)" : currentValue, .current)
        } else if let value = values[parameter.name] ?? defaults[parameter.name] {
          append(value, .filled)
        } else {
          append("$\(parameter.name)", .pending)
        }
      }
    }
    return parts
  }
}
