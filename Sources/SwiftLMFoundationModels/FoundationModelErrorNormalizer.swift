import Foundation
import SwiftLM

#if canImport(FoundationModels) && !os(watchOS)
import FoundationModels
#endif

/// Maps framework errors into `FoundationModelFailure` values.
///
/// On watchOS the framework offers only Private Cloud Compute, which this adapter does not support
/// there yet, so only package errors are normalized.
///
/// Apps built with Xcode 27 receive the OS 27 error taxonomy (`LanguageModelError`,
/// `SystemLanguageModel.Error`, `LanguageModelSession.Error`, and
/// `PrivateCloudComputeLanguageModel.Error`) on OS 27 devices, and the OS 26
/// `LanguageModelSession.GenerationError` cases on OS 26 devices. Both are normalized here.
public enum FoundationModelErrorNormalizer {
  public static func failure(from error: any Error) -> FoundationModelFailure {
    if let failure = error as? FoundationModelFailure {
      return failure
    }

    #if canImport(FoundationModels) && !os(watchOS)
    #if compiler(>=6.4) && !SWIFTLM_OS26_SDK_ONLY
    if #available(iOS 27.0, macOS 27.0, visionOS 27.0, *),
       let failure = foundationModelFailure(fromOS27Error: error)
    {
      return failure
    }
    #endif
    if let generationError = error as? LanguageModelSession.GenerationError {
      return foundationModelFailure(from: generationError)
    }
    if let toolError = error as? LanguageModelSession.ToolCallError {
      return FoundationModelFailure(
        reason: .toolCallFailed,
        debugDescription: toolError.errorDescription ?? String(describing: toolError.underlyingError)
      )
    }
    #endif

    return FoundationModelFailure(
      reason: .providerError,
      debugDescription: error.localizedDescription
    )
  }
}
