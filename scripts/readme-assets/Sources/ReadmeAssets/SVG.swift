import Foundation

// Drawing primitives for the README images: color schemes, text measurement, SVG elements, and a
// small Swift highlighter. Images are plain SVG with system fonts, so they stay sharp, diff as text,
// and render the same on every machine that runs the generator.

enum Scheme: String, CaseIterable, Sendable {
  case light
  case dark
}

struct Hue: Sendable {
  var strong: String
  var soft: String
}

struct CodeColors: Sendable {
  var plain: String
  var keyword: String
  var type: String
  var member: String
  var string: String
  var number: String
  var comment: String
  var gutter: String
}

/// One scheme's colors. Light values sit on GitHub's white page and dark values on its dark page.
struct Palette: Sendable {
  var scheme: Scheme
  var shadowOpacity: Double
  var window: String
  var titleBar: String
  var edge: String
  var dot: String
  var pane: String
  var text: String
  var strong: String
  var muted: String
  var faint: String
  var accent: String
  var success: Hue
  var danger: Hue
  var caution: Hue
  var neutral: Hue
  var track: String
  var chip: String
  var chipText: String
  /// Orange, teal, violet, green, and blue, in that order.
  var hues: [Hue]
  var code: CodeColors

  static func of(_ scheme: Scheme) -> Palette {
    switch scheme {
    case .light: light
    case .dark: dark
    }
  }

  static let light = Palette(
    scheme: .light,
    shadowOpacity: 0.13,
    window: "#FFFFFF",
    titleBar: "#F6F5F4",
    edge: "#E3E0DD",
    dot: "#DCD8D4",
    pane: "#FAF9F8",
    text: "#3F3A36",
    strong: "#1C1917",
    muted: "#78716C",
    faint: "#A8A29E",
    accent: "#EA580C",
    success: Hue(strong: "#15803D", soft: "#DCFCE7"),
    danger: Hue(strong: "#B91C1C", soft: "#FEE2E2"),
    caution: Hue(strong: "#A16207", soft: "#FEF3C7"),
    neutral: Hue(strong: "#57534E", soft: "#F0EEEC"),
    track: "#F1EFED",
    chip: "#F2F0EE",
    chipText: "#44403C",
    hues: [
      Hue(strong: "#C2410C", soft: "#FFEDD5"),
      Hue(strong: "#0F766E", soft: "#CCFBF1"),
      Hue(strong: "#6D28D9", soft: "#EDE9FE"),
      Hue(strong: "#15803D", soft: "#DCFCE7"),
      Hue(strong: "#1D4ED8", soft: "#DBEAFE"),
    ],
    code: CodeColors(
      plain: "#1F2328",
      keyword: "#9B2393",
      type: "#3900A0",
      member: "#6C36A9",
      string: "#C41A16",
      number: "#1C00CF",
      comment: "#707F8C",
      gutter: "#B8B2AC"
    )
  )

  static let dark: Palette = {
    let window = "#15171C"
    func soft(_ color: String, _ alpha: Double = 0.17) -> String {
      Color.blend(color, over: window, alpha: alpha)
    }
    return Palette(
      scheme: .dark,
      shadowOpacity: 0.5,
      window: window,
      titleBar: "#1B1E24",
      edge: "#2B2F37",
      dot: "#3A3F48",
      pane: "#181B20",
      text: "#D4D4D8",
      strong: "#F4F4F5",
      muted: "#A1A1AA",
      faint: "#71717A",
      accent: "#FB923C",
      success: Hue(strong: "#4ADE80", soft: soft("#4ADE80", 0.14)),
      danger: Hue(strong: "#F87171", soft: soft("#F87171")),
      caution: Hue(strong: "#FBBF24", soft: soft("#FBBF24", 0.15)),
      neutral: Hue(strong: "#D4D4D8", soft: "#262A31"),
      track: "#22252C",
      chip: "#23272E",
      chipText: "#E4E4E7",
      hues: [
        Hue(strong: "#FB923C", soft: soft("#FB923C")),
        Hue(strong: "#2DD4BF", soft: soft("#2DD4BF", 0.15)),
        Hue(strong: "#A78BFA", soft: soft("#A78BFA", 0.19)),
        Hue(strong: "#4ADE80", soft: soft("#4ADE80", 0.14)),
        Hue(strong: "#60A5FA", soft: soft("#60A5FA", 0.18)),
      ],
      code: CodeColors(
        plain: "#E4E4E7",
        keyword: "#FC5FA3",
        type: "#D0A8FF",
        member: "#A167E6",
        string: "#FC6A5D",
        number: "#D0BF69",
        comment: "#7F8C98",
        gutter: "#4E535C"
      )
    )
  }()
}

enum Color {
  /// Mixes `color` over `background`, so soft fills stay opaque.
  static func blend(_ color: String, over background: String, alpha: Double) -> String {
    let top = components(color)
    let bottom = components(background)
    let mixed = zip(top, bottom).map { top, bottom in
      Int((Double(bottom) + (Double(top) - Double(bottom)) * alpha).rounded())
    }
    return "#" + mixed.map { String(format: "%02X", $0) }.joined()
  }

  private static func components(_ hex: String) -> [Int] {
    let digits = Array(hex.dropFirst())
    return stride(from: 0, to: 6, by: 2).map { index in
      Int(String(digits[index..<index + 2]), radix: 16) ?? 0
    }
  }
}

enum Fonts {
  static let sans = "ui-sans-serif, -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif"
  static let mono = "ui-monospace, SFMono-Regular, 'SF Mono', Menlo, Consolas, 'Liberation Mono', monospace"
  static let monoAdvance = 0.6

  /// An estimate of rendered width, generous enough that layouts never collide.
  static func sansWidth(_ text: String, size: Double, bold: Bool = false) -> Double {
    let units = text.reduce(0.0) { $0 + advance($1) }
    return units * size * (bold ? 1.07 : 1)
  }

  static func monoWidth(_ text: String, size: Double) -> Double {
    Double(text.count) * size * monoAdvance
  }

  private static func advance(_ character: Character) -> Double {
    switch character {
    case " ": 0.27
    case "i", "l", "j", "'", "|", ".", ",", ":", ";", "!", "I": 0.26
    case "f", "t", "r": 0.35
    case "(", ")", "[", "]", "-", "·": 0.36
    case "m": 0.86
    case "w": 0.75
    case "M", "W": 0.9
    case "0"..."9": 0.59
    default:
      if character.isUppercase { 0.68 }
      else if character.isLowercase { 0.54 }
      else { 0.6 }
    }
  }

  /// Greedy word wrap by estimated width.
  static func wrap(_ text: String, size: Double, width: Double, bold: Bool = false) -> [String] {
    var lines: [String] = []
    var current = ""
    for word in text.split(separator: " ").map(String.init) {
      let candidate = current.isEmpty ? word : current + " " + word
      if sansWidth(candidate, size: size, bold: bold) <= width || current.isEmpty {
        current = candidate
      } else {
        lines.append(current)
        current = word
      }
    }
    if !current.isEmpty { lines.append(current) }
    return lines
  }
}

func escapeXML(_ text: String) -> String {
  text
    .replacingOccurrences(of: "&", with: "&amp;")
    .replacingOccurrences(of: "<", with: "&lt;")
    .replacingOccurrences(of: ">", with: "&gt;")
    .replacingOccurrences(of: "\"", with: "&quot;")
}

func number(_ value: Double) -> String {
  let rounded = (value * 100).rounded() / 100
  if rounded == rounded.rounded() {
    return String(Int(rounded))
  }
  var text = String(format: "%.2f", rounded)
  while text.hasSuffix("0") { text.removeLast() }
  return text
}

func grouped(_ value: Int) -> String {
  let formatter = NumberFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.numberStyle = .decimal
  formatter.usesGroupingSeparator = true
  formatter.groupingSeparator = ","
  formatter.groupingSize = 3
  return formatter.string(from: NSNumber(value: value)) ?? String(value)
}

/// An SVG document built from element strings.
struct SVG {
  var width: Double
  var height: Double
  var label: String
  var definitions: [String] = []
  var elements: [String] = []

  mutating func define(_ element: String) {
    definitions.append(element)
  }

  mutating func add(_ element: String) {
    elements.append(element)
  }

  mutating func add(_ elements: [String]) {
    self.elements.append(contentsOf: elements)
  }

  func render() -> String {
    var lines = [
      #"<svg xmlns="http://www.w3.org/2000/svg" width="\#(number(width))" height="\#(number(height))" viewBox="0 0 \#(number(width)) \#(number(height))" role="img" aria-label="\#(escapeXML(label))">"#,
      "  <title>\(escapeXML(label))</title>",
    ]
    if !definitions.isEmpty {
      lines.append("  <defs>")
      lines.append(contentsOf: definitions.map { "    " + $0 })
      lines.append("  </defs>")
    }
    lines.append(contentsOf: elements.map { "  " + $0 })
    lines.append("</svg>")
    return lines.joined(separator: "\n") + "\n"
  }

  /// The soft shadow under windows and panels, sized for a transparent margin around them.
  static func shadowFilter(id: String, palette: Palette) -> String {
    ##"<filter id="\##(id)" x="-8%" y="-8%" width="116%" height="124%"><feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#000000" flood-opacity="\##(number(palette.shadowOpacity))"/></filter>"##
  }
}

enum Draw {
  static func rect(
    x: Double,
    y: Double,
    width: Double,
    height: Double,
    radius: Double = 0,
    fill: String,
    stroke: String? = nil,
    strokeWidth: Double = 1,
    attributes: String = ""
  ) -> String {
    var element = #"<rect x="\#(number(x))" y="\#(number(y))" width="\#(number(width))" height="\#(number(height))""#
    if radius > 0 { element += #" rx="\#(number(radius))""# }
    element += #" fill="\#(fill)""#
    if let stroke { element += #" stroke="\#(stroke)" stroke-width="\#(number(strokeWidth))""# }
    if !attributes.isEmpty { element += " " + attributes }
    return element + "/>"
  }

  static func circle(x: Double, y: Double, radius: Double, fill: String, attributes: String = "") -> String {
    var element = #"<circle cx="\#(number(x))" cy="\#(number(y))" r="\#(number(radius))" fill="\#(fill)""#
    if !attributes.isEmpty { element += " " + attributes }
    return element + "/>"
  }

  static func line(
    x1: Double,
    y1: Double,
    x2: Double,
    y2: Double,
    stroke: String,
    width: Double = 1,
    attributes: String = ""
  ) -> String {
    var element = #"<line x1="\#(number(x1))" y1="\#(number(y1))" x2="\#(number(x2))" y2="\#(number(y2))" stroke="\#(stroke)" stroke-width="\#(number(width))""#
    if !attributes.isEmpty { element += " " + attributes }
    return element + "/>"
  }

  static func path(_ data: String, fill: String = "none", stroke: String? = nil, width: Double = 2, attributes: String = "") -> String {
    var element = #"<path d="\#(data)" fill="\#(fill)""#
    if let stroke {
      element += #" stroke="\#(stroke)" stroke-width="\#(number(width))" stroke-linecap="round" stroke-linejoin="round""#
    }
    if !attributes.isEmpty { element += " " + attributes }
    return element + "/>"
  }

  static func text(
    _ content: String,
    x: Double,
    y: Double,
    size: Double,
    fill: String,
    bold: Bool = false,
    mono: Bool = false,
    anchor: String = "start",
    attributes: String = ""
  ) -> String {
    var element = #"<text x="\#(number(x))" y="\#(number(y))" font-family="\#(mono ? Fonts.mono : Fonts.sans)" font-size="\#(number(size))""#
    if bold { element += #" font-weight="600""# }
    if anchor != "start" { element += #" text-anchor="\#(anchor)""# }
    element += #" fill="\#(fill)""#
    if !attributes.isEmpty { element += " " + attributes }
    return element + ">" + escapeXML(content) + "</text>"
  }

  /// One line of differently colored runs in a single `<text>` element.
  static func runs(
    _ runs: [(text: String, fill: String, bold: Bool)],
    x: Double,
    y: Double,
    size: Double,
    mono: Bool
  ) -> String {
    let spans = runs.map { run in
      #"<tspan fill="\#(run.fill)"\#(run.bold ? #" font-weight="600""# : "")>\#(escapeXML(run.text))</tspan>"#
    }
    return #"<text x="\#(number(x))" y="\#(number(y))" font-family="\#(mono ? Fonts.mono : Fonts.sans)" font-size="\#(number(size))" xml:space="preserve">\#(spans.joined())</text>"#
  }

  /// A rounded label with centered text. Returns the elements and the pill width.
  static func pill(
    _ label: String,
    x: Double,
    y: Double,
    height: Double = 22,
    size: Double = 11.5,
    hue: Hue,
    mono: Bool = false,
    alignRight: Bool = false
  ) -> (elements: [String], width: Double) {
    let textWidth = mono ? Fonts.monoWidth(label, size: size) : Fonts.sansWidth(label, size: size, bold: true)
    let width = (textWidth + 22).rounded()
    let left = alignRight ? x - width : x
    return (
      [
        rect(x: left, y: y, width: width, height: height, radius: height / 2, fill: hue.soft),
        text(
          label,
          x: left + width / 2,
          y: y + height / 2 + size * 0.36,
          size: size,
          fill: hue.strong,
          bold: !mono,
          mono: mono,
          anchor: "middle"
        ),
      ],
      width
    )
  }

  /// The quiet window chrome: body, title bar, and three dots. Draw `windowBorder` after the
  /// window's contents so the edge stays on top.
  static func window(
    x: Double,
    y: Double,
    width: Double,
    height: Double,
    barHeight: Double,
    palette: Palette,
    shadowID: String
  ) -> [String] {
    let radius = 12.0
    let bar = """
    M \(number(x)) \(number(y + barHeight)) L \(number(x)) \(number(y + radius)) \
    Q \(number(x)) \(number(y)) \(number(x + radius)) \(number(y)) \
    L \(number(x + width - radius)) \(number(y)) \
    Q \(number(x + width)) \(number(y)) \(number(x + width)) \(number(y + radius)) \
    L \(number(x + width)) \(number(y + barHeight)) Z
    """
    return [
      rect(x: x, y: y, width: width, height: height, radius: radius, fill: palette.window, attributes: #"filter="url(#\#(shadowID))""#),
      path(bar, fill: palette.titleBar),
      line(x1: x, y1: y + barHeight, x2: x + width, y2: y + barHeight, stroke: palette.edge),
      circle(x: x + 20, y: y + barHeight / 2, radius: 5.5, fill: palette.dot),
      circle(x: x + 38, y: y + barHeight / 2, radius: 5.5, fill: palette.dot),
      circle(x: x + 56, y: y + barHeight / 2, radius: 5.5, fill: palette.dot),
    ]
  }

  static func windowBorder(x: Double, y: Double, width: Double, height: Double, palette: Palette) -> String {
    rect(x: x + 0.5, y: y + 0.5, width: width - 1, height: height - 1, radius: 11.5, fill: "none", stroke: palette.edge)
  }

  /// A rounded panel with the soft shadow and a hairline edge.
  static func panel(x: Double, y: Double, width: Double, height: Double, palette: Palette, shadowID: String) -> [String] {
    [
      rect(x: x, y: y, width: width, height: height, radius: 16, fill: palette.window, attributes: #"filter="url(#\#(shadowID))""#),
      rect(x: x + 0.5, y: y + 0.5, width: width - 1, height: height - 1, radius: 15.5, fill: "none", stroke: palette.edge),
    ]
  }

  /// A small status mark: a check in a soft circle, or a cross.
  static func statusMark(passed: Bool, x: Double, y: Double, palette: Palette) -> [String] {
    let hue = passed ? palette.success : palette.danger
    let mark = passed
      ? "M \(number(x - 3.6)) \(number(y + 0.2)) l 2.4 2.4 l 4.8 -4.8"
      : "M \(number(x - 3)) \(number(y - 3)) l 6 6 M \(number(x + 3)) \(number(y - 3)) l -6 6"
    return [
      circle(x: x, y: y, radius: 8.5, fill: hue.soft),
      path(mark, stroke: hue.strong, width: 1.8),
    ]
  }

  /// A 24-point line icon drawn at `size` points.
  static func icon(_ icon: Icon, x: Double, y: Double, size: Double, color: String) -> String {
    let scale = size / 24
    let paths = icon.paths.map { path($0, stroke: color, width: 1.8) }.joined()
    let dots = icon.dots.map { circle(x: $0.x, y: $0.y, radius: $0.radius, fill: color) }.joined()
    return #"<g transform="translate(\#(number(x)) \#(number(y))) scale(\#(number(scale)))">\#(paths)\#(dots)</g>"#
  }
}

enum Icon {
  case contract
  case fit
  case route
  case check
  case receipt

  var paths: [String] {
    switch self {
    case .contract:
      ["M6.5 3h8l4 4v14h-12z", "M14.5 3v4h4", "M9.5 12h6", "M9.5 16h6"]
    case .fit:
      ["M3.5 5h17l-6.5 7.5v5.5l-4 2.5v-8z"]
    case .route:
      ["M7 12h3.5", "M10.5 12c3.5 0 3-6 6.5-6", "M10.5 12h6.5", "M10.5 12c3.5 0 3 6 6.5 6"]
    case .check:
      ["M12 3l7 3v5.5c0 4.5-3 7.8-7 9.5-4-1.7-7-5-7-9.5V6z", "M9 12l2.2 2.2 4-4.4"]
    case .receipt:
      ["M6 3h12v18l-2-1.4-2 1.4-2-1.4-2 1.4-2-1.4-2 1.4z", "M9 8h6", "M9 11.5h6", "M9 15h3.5"]
    }
  }

  var dots: [(x: Double, y: Double, radius: Double)] {
    switch self {
    case .route:
      [(4.8, 12, 2.3), (19.2, 6, 1.9), (19.2, 12, 1.9), (19.2, 18, 1.9)]
    default:
      []
    }
  }
}

/// Swift syntax colors close to Xcode's default themes.
enum SwiftHighlighter {
  enum Kind {
    case plain
    case keyword
    case type
    case member
    case string
    case number
    case comment
  }

  static let keywords: Set<String> = [
    "any", "as", "async", "await", "break", "case", "catch", "class", "continue", "default", "defer",
    "do", "else", "enum", "extension", "false", "for", "func", "guard", "if", "import", "in", "init",
    "is", "let", "nil", "private", "public", "return", "self", "Self", "some", "static", "struct",
    "switch", "throw", "throws", "true", "try", "var", "where", "while",
  ]

  static func tokens(_ line: String) -> [(text: String, kind: Kind)] {
    let characters = Array(line)
    var tokens: [(text: String, kind: Kind)] = []
    var index = 0

    func append(_ text: String, _ kind: Kind) {
      if let last = tokens.last, last.kind == kind {
        tokens[tokens.count - 1].text += text
      } else {
        tokens.append((text, kind))
      }
    }

    func previousSignificant(before position: Int) -> Character? {
      var cursor = position - 1
      while cursor >= 0, characters[cursor] == " " { cursor -= 1 }
      return cursor >= 0 ? characters[cursor] : nil
    }

    while index < characters.count {
      let character = characters[index]
      if character == "/", index + 1 < characters.count, characters[index + 1] == "/" {
        append(String(characters[index...]), .comment)
        break
      }
      if character == "\"" {
        var end = index + 1
        while end < characters.count, characters[end] != "\"" {
          end += characters[end] == "\\" ? 2 : 1
        }
        end = min(end + 1, characters.count)
        append(String(characters[index..<end]), .string)
        index = end
        continue
      }
      if character.isNumber {
        var end = index
        while end < characters.count, characters[end].isNumber || characters[end] == "_" || characters[end] == "." {
          end += 1
        }
        append(String(characters[index..<end]), .number)
        index = end
        continue
      }
      if character.isLetter || character == "_" || character == "@" {
        var end = index + 1
        while end < characters.count, characters[end].isLetter || characters[end].isNumber || characters[end] == "_" {
          end += 1
        }
        let word = String(characters[index..<end])
        let kind: Kind
        if keywords.contains(word) || word.hasPrefix("@") {
          kind = .keyword
        } else if previousSignificant(before: index) == "." {
          kind = .member
        } else if word.first?.isUppercase == true {
          kind = .type
        } else {
          kind = .plain
        }
        append(word, kind)
        index = end
        continue
      }
      append(String(character), .plain)
      index += 1
    }
    return tokens
  }

  static func color(_ kind: Kind, in colors: CodeColors) -> String {
    switch kind {
    case .plain: colors.plain
    case .keyword: colors.keyword
    case .type: colors.type
    case .member: colors.member
    case .string: colors.string
    case .number: colors.number
    case .comment: colors.comment
    }
  }
}
