import Foundation

/// Regenerates the README images and generated README blocks from real SwiftLM output.
///
///     swift run --package-path scripts/readme-assets ReadmeAssets            # write
///     swift run --package-path scripts/readme-assets ReadmeAssets --check    # fail on drift
///
/// `--check` writes nothing. It fails when an image or a generated block differs from what the
/// package produces now, when a README Swift block is not a compiled snippet, or when
/// `docs/assets/readme` holds a file the generator does not make.
@main
struct ReadmeAssets {
  static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

  static let assetDirectory = "docs/assets/readme"

  static func main() async {
    let check = CommandLine.arguments.dropFirst().contains("--check")
    do {
      let problems = try await run(check: check)
      guard problems.isEmpty else {
        for problem in problems {
          FileHandle.standardError.write(Data((problem + "\n").utf8))
        }
        FileHandle.standardError.write(
          Data("Run `swift run --package-path scripts/readme-assets ReadmeAssets` to regenerate.\n".utf8)
        )
        exit(1)
      }
      print(check ? "README assets are current." : "README assets are up to date.")
    } catch {
      FileHandle.standardError.write(Data("README asset generation failed: \(error)\n".utf8))
      exit(1)
    }
  }

  static func run(check: Bool) async throws -> [String] {
    guard Images.steps.map(\.symbol) == Images.stepSymbols else {
      return ["The flow diagram names a type that does not match Images.stepSymbols."]
    }

    let regions = try SnippetSource.regions()
    guard let routeCode = regions.first(where: { $0.name == "route" })?.code else {
      return ["Snippets.swift has no route snippet for the hero image."]
    }
    let receipt = try await Demo.route()
    let budgets = Demo.budgets()
    let reports = try await Demo.evaluations()

    var files: [String: String] = ["\(assetDirectory)/mark.svg": Images.mark()]
    for scheme in Scheme.allCases {
      let suffix = scheme.rawValue
      files["\(assetDirectory)/hero-\(suffix).svg"] = Images.hero(scheme, code: routeCode, receipt: receipt)
      files["\(assetDirectory)/flow-\(suffix).svg"] = Images.flow(scheme)
      files["\(assetDirectory)/budget-\(suffix).svg"] = Images.budget(scheme, runs: budgets, sources: Demo.snippets())
      files["\(assetDirectory)/evaluation-\(suffix).svg"] = Images.evaluation(
        scheme,
        cases: Demo.evaluationCases,
        reports: reports
      )
    }

    var problems: [String] = []
    let fileManager = FileManager.default
    for (path, content) in files.sorted(by: { $0.key < $1.key }) {
      let url = root.appending(path: path)
      if (try? String(contentsOf: url, encoding: .utf8)) == content { continue }
      if check {
        problems.append("\(path) is out of date.")
      } else {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        print("wrote \(path)")
      }
    }

    let directory = root.appending(path: assetDirectory)
    let existing = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
    for name in existing.sorted() where files["\(assetDirectory)/\(name)"] == nil && !name.hasPrefix(".") {
      problems.append("\(assetDirectory)/\(name) is not made by the generator. Remove it or add it to ReadmeAssets.")
    }

    var blocks = [
      "capabilities": CapabilityTable.markdown(),
      "receipt": try ReceiptBlock.markdown(receipt),
    ]
    for name in ["hero", "flow", "budget", "evaluation"] {
      blocks["\(name)-image"] = try PictureBlock.markdown(
        name: name,
        directory: assetDirectory,
        lightSVG: files["\(assetDirectory)/\(name)-light.svg"] ?? ""
      )
    }

    let readmeURL = root.appending(path: "README.md")
    let readme = try String(contentsOf: readmeURL, encoding: .utf8)
    let updated = try GeneratedBlocks.apply(blocks, to: readme)
    if updated != readme {
      if check {
        problems.append("README.md generated blocks are out of date.")
      } else {
        try updated.write(to: readmeURL, atomically: true, encoding: .utf8)
        print("updated README.md")
      }
    }

    problems += SnippetCheck.problems(readme: updated, regions: regions)
    return problems
  }
}
