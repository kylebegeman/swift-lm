import Foundation
import SwiftLM
import SwiftLMEvaluation

/// The README images. Each takes real output from `Demo` and lays it out for one color scheme.
enum Images {
  static let canvasWidth = 1040.0

  // MARK: - Mark

  static func mark() -> String {
    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" role="img" aria-labelledby="swiftlm-mark-title">
      <title id="swiftlm-mark-title">SwiftLM</title>
      <defs>
        <linearGradient id="swiftlm-mark-fill" x1="6" y1="4" x2="58" y2="60" gradientUnits="userSpaceOnUse">
          <stop offset="0" stop-color="#FDBA74"/>
          <stop offset="0.5" stop-color="#F97316"/>
          <stop offset="1" stop-color="#C2410C"/>
        </linearGradient>
      </defs>
      <path d="M18 5h28a14 14 0 0 1 14 14v15a14 14 0 0 1-14 14H28.5l-12.2 9.9c-1.3 1.1-3.3.1-3.3-1.6v-8.9A14 14 0 0 1 4 34V19A14 14 0 0 1 18 5z" fill="url(#swiftlm-mark-fill)"/>
      <g fill="none" stroke="#FFFFFF" stroke-width="3.4" stroke-linecap="round">
        <path d="M21 26.5h5.5"/>
        <path d="M26.5 26.5c6 0 6.5-9 13.5-9"/>
        <path d="M26.5 26.5h13.5"/>
        <path d="M26.5 26.5c6 0 6.5 9 13.5 9"/>
      </g>
      <circle cx="18" cy="26.5" r="4.6" fill="#FFFFFF"/>
      <circle cx="43.5" cy="17.5" r="3.6" fill="#FFFFFF"/>
      <circle cx="43.5" cy="26.5" r="3.6" fill="#FFFFFF"/>
      <circle cx="43.5" cy="35.5" r="3.6" fill="#FFFFFF"/>
    </svg>

    """
  }

  // MARK: - Hero

  static func providerName(_ provider: LMProviderReceiptSnapshot) -> String {
    guard provider.providerKind == LMProviderKind.appleFoundationModels.rawValue else {
      return provider.providerDisplayName
    }
    return provider.privacyMode == LMPrivacyMode.privateCloudCompute.rawValue
      ? "Private Cloud Compute"
      : "On-device model"
  }

  static func statusLabel(_ status: LMRunAttemptStatus) -> String {
    switch status {
    case .skippedUnsupportedCapabilities: "Skipped"
    case .failed: "Failed"
    case .succeeded: "Succeeded"
    }
  }

  static func heroLabel(_ receipt: LMRunReceipt) -> String {
    var attempts = receipt.attempts.map { attempt -> String in
      var name = providerName(attempt.provider)
      if name == "On-device model" { name = "the on-device model" }
      switch attempt.status {
      case .skippedUnsupportedCapabilities:
        return "\(name) was skipped because the request needs \(attempt.unsupportedCapabilities.joined(separator: " and "))"
      case .failed:
        return "\(name) failed with \(attempt.error?.fallbackReason ?? "an error")"
      case .succeeded:
        return "\(name) answered"
      }
    }
    if attempts.count > 1 {
      attempts[attempts.count - 1] = "and " + attempts[attempts.count - 1]
    }
    return "Swift code that routes one request from the on-device model to Private Cloud Compute to Claude, "
      + "beside the run receipt it produced: " + attempts.joined(separator: ", ") + "."
  }

  static func hero(_ scheme: Scheme, code: String, receipt: LMRunReceipt) -> String {
    let palette = Palette.of(scheme)
    let lines = code.components(separatedBy: "\n")
    let (x, y, width) = (24.0, 18.0, 992.0)
    let (barHeight, headerHeight) = (36.0, 42.0)
    let split = x + 540
    let codeSize = 13.0
    let lineHeight = 20.0
    let bodyTop = y + barHeight + headerHeight
    let cardHeight = 92.0
    let cardGap = 12.0
    let attempts = receipt.attempts
    let cardsHeight = Double(attempts.count) * cardHeight + Double(max(0, attempts.count - 1)) * cardGap
    let receiptHeight = 18 + cardsHeight + 30 + 3 * 26 + 12
    let codeHeight = 18 + Double(lines.count) * lineHeight + 18
    let windowHeight = barHeight + headerHeight + max(codeHeight, receiptHeight)
    var svg = SVG(width: canvasWidth, height: y + windowHeight + 40, label: heroLabel(receipt))
    svg.define(SVG.shadowFilter(id: "shadow", palette: palette))
    svg.define(#"<clipPath id="window"><rect x="\#(number(x))" y="\#(number(y))" width="\#(number(width))" height="\#(number(windowHeight))" rx="12"/></clipPath>"#)

    svg.add(Draw.window(x: x, y: y, width: width, height: windowHeight, barHeight: barHeight, palette: palette, shadowID: "shadow"))
    svg.add(
      #"<g clip-path="url(#window)">"#
        + Draw.rect(x: split, y: y + barHeight, width: x + width - split, height: windowHeight - barHeight, fill: palette.pane)
        + "</g>"
    )
    svg.add(Draw.line(x1: x, y1: bodyTop, x2: x + width, y2: bodyTop, stroke: palette.edge))
    svg.add(Draw.line(x1: split, y1: y + barHeight, x2: split, y2: y + windowHeight, stroke: palette.edge))

    // The file tab.
    let tabTitle = "MeetingActions.swift"
    let tabWidth = Fonts.sansWidth(tabTitle, size: 12.5, bold: true) + 44
    svg.add(Draw.rect(x: x + 18, y: y + barHeight + 15, width: 12, height: 12, radius: 3, fill: palette.accent))
    svg.add(Draw.path("M \(number(x + 21)) \(number(y + barHeight + 24)) l 3 -6 l 3 6", stroke: palette.window, width: 1.4))
    svg.add(Draw.text(tabTitle, x: x + 38, y: y + barHeight + 25.5, size: 12.5, fill: palette.strong, bold: true))
    svg.add(Draw.rect(x: x + 12, y: bodyTop - 2, width: tabWidth, height: 2, fill: palette.accent))

    // The receipt header.
    svg.add(Draw.text("Run receipt", x: split + 20, y: y + barHeight + 25.5, size: 12.5, fill: palette.strong, bold: true))
    let outcomeHue = receipt.outcome == .succeeded ? palette.success : palette.danger
    let outcome = Draw.pill(
      receipt.outcome == .succeeded ? "Succeeded" : "Failed",
      x: x + width - 18,
      y: y + barHeight + 10,
      hue: outcomeHue,
      alignRight: true
    )
    svg.add(outcome.elements)
    let attemptsLabel = "\(attempts.count) attempts"
    svg.add(
      Draw.text(
        attemptsLabel,
        x: x + width - 18 - outcome.width - 10,
        y: y + barHeight + 25.5,
        size: 12.5,
        fill: palette.muted,
        anchor: "end"
      )
    )

    // Code.
    for (index, line) in lines.enumerated() {
      let baseline = bodyTop + 18 + Double(index) * lineHeight + 14
      svg.add(
        Draw.text(
          String(index + 1),
          x: x + 42,
          y: baseline,
          size: codeSize - 1,
          fill: palette.code.gutter,
          mono: true,
          anchor: "end"
        )
      )
      guard !line.isEmpty else { continue }
      let runs = SwiftHighlighter.tokens(line).map { token in
        (
          text: token.text,
          fill: SwiftHighlighter.color(token.kind, in: palette.code),
          bold: token.kind == .keyword
        )
      }
      svg.add(Draw.runs(runs, x: x + 58, y: baseline, size: codeSize, mono: true))
    }

    // Attempts.
    let left = split + 20
    let cardWidth = x + width - 20 - left
    for (index, attempt) in attempts.enumerated() {
      let top = bodyTop + 18 + Double(index) * (cardHeight + cardGap)
      svg.add(Draw.rect(x: left, y: top, width: cardWidth, height: cardHeight, radius: 12, fill: palette.window, stroke: palette.edge))
      svg.add(Draw.circle(x: left + 26, y: top + 30, radius: 13, fill: palette.neutral.soft))
      svg.add(Draw.text(String(index + 1), x: left + 26, y: top + 34.5, size: 12.5, fill: palette.neutral.strong, bold: true, anchor: "middle"))
      svg.add(Draw.text(providerName(attempt.provider), x: left + 50, y: top + 28, size: 14.5, fill: palette.strong, bold: true))
      svg.add(
        Draw.text(
          attempt.provider.modelIdentifier ?? attempt.provider.providerDisplayName,
          x: left + 50,
          y: top + 46,
          size: 11.5,
          fill: palette.muted,
          mono: true
        )
      )

      let statusHue: Hue = switch attempt.status {
      case .skippedUnsupportedCapabilities: palette.caution
      case .failed: palette.danger
      case .succeeded: palette.success
      }
      svg.add(Draw.pill(statusLabel(attempt.status), x: left + cardWidth - 14, y: top + 16, hue: statusHue, alignRight: true).elements)

      let detailBaseline = top + 76
      switch attempt.status {
      case .skippedUnsupportedCapabilities:
        svg.add(Draw.text("The request needs", x: left + 16, y: detailBaseline, size: 13, fill: palette.text))
        let chipX = left + 16 + Fonts.sansWidth("The request needs", size: 13) + 8
        svg.add(chip(attempt.unsupportedCapabilities.joined(separator: ", "), x: chipX, baseline: detailBaseline, palette: palette))
      case .failed:
        svg.add(Draw.text("Fallback reason", x: left + 16, y: detailBaseline, size: 13, fill: palette.text))
        let chipX = left + 16 + Fonts.sansWidth("Fallback reason", size: 13) + 8
        svg.add(chip(attempt.error?.fallbackReason ?? "unknown", x: chipX, baseline: detailBaseline, palette: palette))
      case .succeeded:
        let usage = attempt.tokenUsage
        let input = usage?.measuredInputTokens ?? usage?.estimatedInputTokens ?? 0
        let output = usage?.measuredOutputTokens ?? usage?.estimatedOutputTokens ?? 0
        svg.add(
          Draw.runs(
            [
              (text: grouped(input), fill: palette.strong, bold: true),
              (text: " tokens in, ", fill: palette.text, bold: false),
              (text: grouped(output), fill: palette.strong, bold: true),
              (text: " out", fill: palette.text, bold: false),
            ],
            x: left + 16,
            y: detailBaseline,
            size: 13,
            mono: false
          )
        )
      }
      let privacy = attempt.provider.privacyMode
      let privacyWidth = Fonts.monoWidth(privacy, size: 11) + 16
      svg.add(chip(privacy, x: left + cardWidth - 14 - privacyWidth, baseline: detailBaseline, palette: palette, size: 11, muted: true))
    }

    // What every receipt keeps.
    let listTop = bodyTop + 18 + cardsHeight + 30
    let facts: [(Bool, String)] = [
      (true, "Providers, models, and privacy modes"),
      (true, "Statuses, fallback reasons, and token counts"),
      (false, "Never the prompt or the response text"),
    ]
    for (index, fact) in facts.enumerated() {
      let center = listTop + Double(index) * 26
      svg.add(Draw.statusMark(passed: fact.0, x: left + 9, y: center, palette: palette))
      svg.add(Draw.text(fact.1, x: left + 28, y: center + 4.5, size: 13, fill: palette.text))
    }

    svg.add(
      Draw.text(
        "Model replies are scripted. The routing and the receipt are real.",
        x: left,
        y: y + windowHeight - 18,
        size: 11.5,
        fill: palette.faint
      )
    )

    svg.add(Draw.windowBorder(x: x, y: y, width: width, height: windowHeight, palette: palette))
    return svg.render()
  }

  /// A code-styled chip on a text baseline. Returns one group element.
  static func chip(
    _ label: String,
    x: Double,
    baseline: Double,
    palette: Palette,
    size: Double = 12,
    muted: Bool = false
  ) -> String {
    let width = Fonts.monoWidth(label, size: size) + 16
    return "<g>"
      + Draw.rect(x: x, y: baseline - size - 4, width: width, height: size + 10, radius: 6, fill: palette.chip)
      + Draw.text(label, x: x + 8, y: baseline, size: size, fill: muted ? palette.muted : palette.chipText, mono: true)
      + "</g>"
  }

  // MARK: - Flow

  struct Step {
    var icon: Icon
    var title: String
    var summary: String
    var symbol: String
  }

  static let steps = [
    Step(icon: .contract, title: "Describe", summary: "A versioned contract says what the feature asks.", symbol: "PromptContract"),
    Step(icon: .fit, title: "Fit", summary: "Sources are packed into the model's token budget.", symbol: "LMContextCompiler"),
    Step(icon: .route, title: "Route", summary: "The first model that can honor the request answers.", symbol: "LMRouter"),
    Step(icon: .check, title: "Check", summary: "Output is checked against the sources.", symbol: "GroundingValidator"),
    Step(icon: .receipt, title: "Record", summary: "A redacted receipt says what ran and why.", symbol: "LMRunReceipt"),
  ]

  /// Compile-time proof that every step names a real type.
  static let stepSymbols: [String] = [
    String(describing: PromptContract.self),
    String(describing: LMContextCompiler.self),
    String(describing: LMRouter.self),
    String(describing: GroundingValidator.self),
    String(describing: LMRunReceipt.self),
  ]

  static let flowCaption = "then evaluation cases replay the feature when a prompt or a model changes"

  static func flow(_ scheme: Scheme) -> String {
    let palette = Palette.of(scheme)
    let (x, y, width) = (24.0, 18.0, 992.0)
    let inset = 34.0
    let gap = 30.0
    let columnWidth = (width - inset * 2 - gap * Double(steps.count - 1)) / Double(steps.count)
    let top = y + 34
    let panelHeight = 280.0
    let label = "How SwiftLM runs a feature: "
      + steps.map { "\($0.title), \($0.summary.prefix(1).lowercased())\($0.summary.dropFirst().dropLast())" }.joined(separator: "; ")
      + "; " + flowCaption + "."
    var svg = SVG(width: canvasWidth, height: y + panelHeight + 34, label: label)
    svg.define(SVG.shadowFilter(id: "shadow", palette: palette))
    svg.define(#"<marker id="arrow" viewBox="0 0 10 10" refX="7" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" fill="\#(palette.faint)"/></marker>"#)
    svg.add(Draw.panel(x: x, y: y, width: width, height: panelHeight, palette: palette, shadowID: "shadow"))

    for (index, step) in steps.enumerated() {
      let hue = palette.hues[index % palette.hues.count]
      let left = x + inset + Double(index) * (columnWidth + gap)
      svg.add(Draw.circle(x: left + 17, y: top + 17, radius: 17, fill: hue.soft))
      svg.add(Draw.text(String(index + 1), x: left + 17, y: top + 22.5, size: 15, fill: hue.strong, bold: true, anchor: "middle"))
      svg.add(Draw.rect(x: left + 44, y: top, width: 34, height: 34, radius: 9, fill: "none", stroke: hue.strong, strokeWidth: 1.6))
      svg.add(Draw.icon(step.icon, x: left + 49, y: top + 5, size: 24, color: hue.strong))
      svg.add(Draw.text(step.title, x: left, y: top + 74, size: 22, fill: palette.strong, bold: true))
      for (lineIndex, line) in Fonts.wrap(step.summary, size: 14, width: columnWidth).enumerated() {
        svg.add(Draw.text(line, x: left, y: top + 100 + Double(lineIndex) * 20.5, size: 14, fill: palette.muted))
      }
      svg.add(chip(step.symbol, x: left, baseline: top + 178, palette: palette, size: 11.5))

      if index < steps.count - 1 {
        svg.add(
          Draw.line(
            x1: left + 94,
            y1: top + 17,
            x2: left + columnWidth + gap - 14,
            y2: top + 17,
            stroke: palette.faint,
            width: 1.6,
            attributes: #"stroke-linecap="round" marker-end="url(#arrow)""#
          )
        )
      }
    }

    let captionY = top + 222
    let captionWidth = Fonts.sansWidth(flowCaption, size: 14) + 36
    let center = x + width / 2
    let dash = #"stroke-dasharray="5 6""#
    svg.add(Draw.line(x1: x + inset, y1: captionY - 5, x2: center - captionWidth / 2, y2: captionY - 5, stroke: palette.edge, width: 1.4, attributes: dash))
    svg.add(Draw.line(x1: center + captionWidth / 2, y1: captionY - 5, x2: x + width - inset, y2: captionY - 5, stroke: palette.edge, width: 1.4, attributes: dash))
    svg.add(Draw.text(flowCaption, x: center, y: captionY, size: 14, fill: palette.muted, anchor: "middle"))
    return svg.render()
  }

  // MARK: - Budget

  static func budget(_ scheme: Scheme, runs: [Demo.BudgetRun], sources: [RetrievedSnippet]) -> String {
    let palette = Palette.of(scheme)
    let (x, y, width) = (24.0, 18.0, 992.0)
    let inset = 34.0
    let barLeft = x + 236
    let barWidth = x + width - inset - barLeft
    let rowsTop = y + 104
    let rowHeight = 92.0
    let tableTop = rowsTop + Double(runs.count) * rowHeight + 16
    let tableRow = 32.0
    let panelHeight = tableTop - y + 34 + Double(sources.count) * tableRow + 24

    let summaries = runs.map { run -> String in
      "\(run.title) packs \(run.result.packedSnippets.count) of \(sources.count) sources into \(grouped(run.budget.contextLimit)) tokens"
    }
    var svg = SVG(
      width: canvasWidth,
      height: y + panelHeight + 34,
      label: "LMContextCompiler fitting one meeting note and five local sources into two context windows. "
        + summaries.joined(separator: ". ") + "."
    )
    svg.define(SVG.shadowFilter(id: "shadow", palette: palette))
    svg.define(
      #"<pattern id="hatch" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">"#
        + Draw.rect(x: 0, y: 0, width: 6, height: 6, fill: palette.track)
        + Draw.line(x1: 0, y1: 0, x2: 0, y2: 6, stroke: palette.faint, width: 1.4)
        + "</pattern>"
    )
    svg.add(Draw.panel(x: x, y: y, width: width, height: panelHeight, palette: palette, shadowID: "shadow"))
    svg.add(Draw.text("One meeting note, five local sources, two context windows", x: x + inset, y: y + 44, size: 17, fill: palette.strong, bold: true))
    svg.add(
      Draw.text(
        "The compiler packs the highest-scoring sources that fit and reports the ones it left out.",
        x: x + inset,
        y: y + 68,
        size: 13.5,
        fill: palette.muted
      )
    )

    let instructionsHue = palette.hues[0]
    let noteHue = palette.hues[4]
    let sourceHue = palette.hues[1]
    let answerHue = palette.hues[2]

    for (index, run) in runs.enumerated() {
      let top = rowsTop + Double(index) * rowHeight
      let limit = Double(run.budget.contextLimit)
      let scale = barWidth / limit
      let items = run.result.plan.items
      func tokens(_ surface: LMContextSurface) -> Int {
        items.filter { $0.surface == surface }.reduce(0) { $0 + $1.tokenCount() }
      }
      let instructionTokens = tokens(.instructions)
      let noteTokens = tokens(.prompt)
      let sourceTokens = tokens(.retrievedContext)
      let free = run.result.budgetReport.remainingInputTokens
      let reserved = run.budget.reservedResponseTokens
      let margin = run.budget.safetyMarginTokens

      svg.add(Draw.text(run.title, x: x + inset, y: top + 16, size: 15, fill: palette.strong, bold: true))
      svg.add(Draw.text("\(grouped(run.budget.contextLimit))-token window", x: x + inset, y: top + 36, size: 12, fill: palette.muted, mono: true))

      let barTop = top
      let barHeight = 30.0
      let clipID = "bar-\(index)"
      svg.define(#"<clipPath id="\#(clipID)"><rect x="\#(number(barLeft))" y="\#(number(barTop))" width="\#(number(barWidth))" height="\#(number(barHeight))" rx="7"/></clipPath>"#)
      var segments: [String] = [Draw.rect(x: barLeft, y: barTop, width: barWidth, height: barHeight, fill: palette.track)]
      var cursor = barLeft
      func segment(_ tokenCount: Int, _ hue: Hue, label: String? = nil) {
        let segmentWidth = Double(tokenCount) * scale
        guard segmentWidth > 0 else { return }
        segments.append(Draw.rect(x: cursor, y: barTop, width: segmentWidth, height: barHeight, fill: hue.soft))
        segments.append(Draw.rect(x: cursor, y: barTop, width: max(segmentWidth - 1.5, 0.5), height: 3, fill: hue.strong))
        if let label, segmentWidth >= Fonts.monoWidth(label, size: 11) + 8 {
          segments.append(Draw.text(label, x: cursor + segmentWidth / 2, y: barTop + 20.5, size: 11, fill: hue.strong, mono: true, anchor: "middle"))
        }
        cursor += segmentWidth
        segments.append(Draw.rect(x: cursor - 1.5, y: barTop, width: 1.5, height: barHeight, fill: palette.window))
      }
      segment(instructionTokens, instructionsHue)
      segment(noteTokens, noteHue)
      let packedTotal = max(1, run.result.packedSnippets.reduce(0) { $0 + $1.tokenCount })
      for citation in run.result.citations {
        guard let snippet = run.result.packedSnippets.first(where: { $0.id == citation.snippetID }) else { continue }
        let share = Int((Double(sourceTokens) * Double(snippet.tokenCount) / Double(packedTotal)).rounded())
        segment(share, sourceHue, label: "[\(citation.marker)]")
      }
      cursor = barLeft + barWidth - Double(reserved + margin) * scale
      let answerWidth = Double(reserved) * scale
      segments.append(Draw.rect(x: cursor, y: barTop, width: answerWidth, height: barHeight, fill: answerHue.soft))
      segments.append(Draw.rect(x: cursor + 1.5, y: barTop, width: answerWidth - 3, height: 3, fill: answerHue.strong))
      if answerWidth >= Fonts.sansWidth("answer", size: 11) + 10 {
        segments.append(Draw.text("answer", x: cursor + answerWidth / 2, y: barTop + 20.5, size: 11, fill: answerHue.strong, anchor: "middle"))
      }
      segments.append(
        Draw.rect(
          x: cursor + answerWidth,
          y: barTop,
          width: Double(margin) * scale,
          height: barHeight,
          fill: "url(#hatch)"
        )
      )
      segments.append(Draw.rect(x: cursor, y: barTop, width: 1.5, height: barHeight, fill: palette.window))
      segments.append(Draw.rect(x: cursor + answerWidth - 1.5, y: barTop, width: 1.5, height: barHeight, fill: palette.window))
      svg.add(#"<g clip-path="url(#\#(clipID))">"# + segments.joined() + "</g>")
      svg.add(Draw.rect(x: barLeft + 0.5, y: barTop + 0.5, width: barWidth - 1, height: barHeight - 1, radius: 6.5, fill: "none", stroke: palette.edge))

      let legend: [(Int, String, String)] = [
        (instructionTokens, "instructions", instructionsHue.strong),
        (noteTokens, "note", noteHue.strong),
        (sourceTokens, "sources", sourceHue.strong),
        (free, "free", palette.muted),
        (reserved, "answer", answerHue.strong),
        (margin, "margin", palette.muted),
      ]
      var legendRuns: [(text: String, fill: String, bold: Bool)] = []
      for (legendIndex, entry) in legend.enumerated() {
        if legendIndex > 0 { legendRuns.append((text: "   ", fill: palette.muted, bold: false)) }
        legendRuns.append((text: grouped(entry.0), fill: entry.2, bold: true))
        legendRuns.append((text: " " + entry.1, fill: palette.muted, bold: false))
      }
      svg.add(Draw.runs(legendRuns, x: barLeft, y: barTop + barHeight + 22, size: 12.5, mono: false))
    }

    // Sources.
    let columns = (source: x + inset, tokens: x + 500, score: x + 576, first: x + 626, second: x + 786)
    let headerY = tableTop + 18
    svg.add(Draw.line(x1: x + inset, y1: tableTop, x2: x + width - inset, y2: tableTop, stroke: palette.edge))
    for (text, xPosition, anchor) in [
      ("SOURCE", columns.source, "start"),
      ("TOKENS", columns.tokens, "end"),
      ("SCORE", columns.score, "end"),
      (runs[0].title.uppercased(), columns.first, "start"),
      (runs[1].title.uppercased(), columns.second, "start"),
    ] {
      svg.add(Draw.text(text, x: xPosition, y: headerY + 8, size: 10.5, fill: palette.muted, bold: true, anchor: anchor, attributes: #"letter-spacing="0.6""#))
    }
    for (index, source) in sources.enumerated() {
      let baseline = tableTop + 34 + Double(index) * tableRow + 18
      svg.add(Draw.text(source.sourceDisplayName ?? source.id, x: columns.source, y: baseline, size: 13.5, fill: palette.strong))
      svg.add(Draw.text(grouped(source.tokenCount), x: columns.tokens, y: baseline, size: 12.5, fill: palette.text, mono: true, anchor: "end"))
      svg.add(Draw.text(String(format: "%.2f", source.score), x: columns.score, y: baseline, size: 12.5, fill: palette.text, mono: true, anchor: "end"))
      for (runIndex, run) in runs.prefix(2).enumerated() {
        let column = runIndex == 0 ? columns.first : columns.second
        if let citation = run.result.citations.first(where: { $0.snippetID == source.id }) {
          svg.add(Draw.pill("Packed as [\(citation.marker)]", x: column, y: baseline - 15.5, hue: sourceHue).elements)
        } else {
          svg.add(Draw.pill("Left out", x: column, y: baseline - 15.5, hue: palette.danger).elements)
        }
      }
    }
    return svg.render()
  }

  // MARK: - Evaluation

  static func caseSummary(_ evaluationCase: PromptEvaluationCase) -> String {
    var parts: [String] = []
    if !evaluationCase.requiredSubstrings.isEmpty {
      parts.append("Requires " + evaluationCase.requiredSubstrings.joined(separator: " and "))
    }
    if !evaluationCase.forbiddenSubstrings.isEmpty {
      parts.append("Forbids " + evaluationCase.forbiddenSubstrings.joined(separator: " and "))
    }
    for assertion in evaluationCase.assertions {
      switch assertion {
      case let .maximumLength(length): parts.append("At most \(length) characters")
      case let .minimumLength(length): parts.append("At least \(length) characters")
      case let .contains(text): parts.append("Contains \(text)")
      case let .excludes(text): parts.append("Excludes \(text)")
      case let .minimumOccurrences(text, count): parts.append("\(text) at least \(count) times")
      }
    }
    return parts.joined(separator: ", ")
  }

  static func evaluation(
    _ scheme: Scheme,
    cases: [PromptEvaluationCase],
    reports: [PromptVersionEvaluationReport]
  ) -> String {
    let palette = Palette.of(scheme)
    let (x, y, width) = (24.0, 18.0, 992.0)
    let inset = 34.0
    let caseColumn = x + inset
    let versionColumns = [x + 350, x + 670]
    let cellWidth = 290.0
    let tableTop = y + 100
    let rowHeight = 70.0
    let panelHeight = tableTop - y + 44 + Double(cases.count) * rowHeight + 48

    let summaries = reports.map { report in
      let passed = report.caseResults.filter(\.passed).count
      return "version \(report.promptVersion) passes \(passed) of \(report.caseResults.count)"
    }
    var svg = SVG(
      width: canvasWidth,
      height: y + panelHeight + 34,
      label: "Prompt evaluation for meeting-actions: " + summaries.joined(separator: ", ") + "."
    )
    svg.define(SVG.shadowFilter(id: "shadow", palette: palette))
    svg.add(Draw.panel(x: x, y: y, width: width, height: panelHeight, palette: palette, shadowID: "shadow"))
    let promptID = reports.first?.promptID ?? ""
    svg.add(
      Draw.runs(
        [
          (text: promptID, fill: palette.strong, bold: true),
          (text: "  two prompt versions, three cases", fill: palette.muted, bold: false),
        ],
        x: x + inset,
        y: y + 44,
        size: 17,
        mono: false
      )
    )
    svg.add(
      Draw.text(
        "PromptEvaluator runs the same cases against each version and keeps the failure messages.",
        x: x + inset,
        y: y + 68,
        size: 13.5,
        fill: palette.muted
      )
    )

    svg.add(Draw.line(x1: x + inset, y1: tableTop, x2: x + width - inset, y2: tableTop, stroke: palette.edge))
    svg.add(Draw.text("CASE", x: caseColumn, y: tableTop + 27, size: 10.5, fill: palette.muted, bold: true, attributes: #"letter-spacing="0.6""#))
    for (index, report) in reports.prefix(2).enumerated() {
      let column = versionColumns[index]
      svg.add(Draw.text(report.promptVersion, x: column, y: tableTop + 27, size: 13, fill: palette.strong, bold: true, mono: true))
      let passed = report.caseResults.filter(\.passed).count
      let hue = passed == report.caseResults.count ? palette.success : palette.danger
      svg.add(
        Draw.pill(
          "\(passed) of \(report.caseResults.count) passed",
          x: column + Fonts.monoWidth(report.promptVersion, size: 13) + 12,
          y: tableTop + 12,
          hue: hue
        ).elements
      )
    }

    for (rowIndex, evaluationCase) in cases.enumerated() {
      let top = tableTop + 44 + Double(rowIndex) * rowHeight
      svg.add(Draw.line(x1: x + inset, y1: top, x2: x + width - inset, y2: top, stroke: palette.edge))
      svg.add(Draw.text(evaluationCase.id, x: caseColumn, y: top + 28, size: 13.5, fill: palette.strong, bold: true, mono: true))
      svg.add(Draw.text(caseSummary(evaluationCase), x: caseColumn, y: top + 49, size: 12.5, fill: palette.muted))
      for (index, report) in reports.prefix(2).enumerated() {
        let column = versionColumns[index]
        guard let result = report.caseResults.first(where: { $0.caseID == evaluationCase.id }) else { continue }
        svg.add(Draw.statusMark(passed: result.passed, x: column + 9, y: top + 24, palette: palette))
        if result.passed {
          svg.add(Draw.text("Passed", x: column + 28, y: top + 28.5, size: 13.5, fill: palette.success.strong, bold: true))
        } else {
          let message = result.failures.joined(separator: " ")
          for (lineIndex, line) in Fonts.wrap(message, size: 13, width: cellWidth - 28).prefix(2).enumerated() {
            svg.add(Draw.text(line, x: column + 28, y: top + 28.5 + Double(lineIndex) * 19, size: 13, fill: palette.text))
          }
        }
      }
    }

    let footerY = tableTop + 44 + Double(cases.count) * rowHeight
    svg.add(Draw.line(x1: x + inset, y1: footerY, x2: x + width - inset, y2: footerY, stroke: palette.edge))
    let storesOutputs = reports.contains(where: \.storesRawOutputs)
    svg.add(
      Draw.text(
        storesOutputs
          ? "Reports keep case IDs, results, failure messages, and model outputs."
          : "Reports keep case IDs, results, and failure messages. Model outputs stay out unless you opt in.",
        x: x + inset,
        y: footerY + 26,
        size: 12.5,
        fill: palette.muted
      )
    )
    return svg.render()
  }
}
