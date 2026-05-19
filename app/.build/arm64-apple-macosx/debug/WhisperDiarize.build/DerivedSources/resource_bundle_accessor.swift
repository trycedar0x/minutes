import Foundation

extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("WhisperDiarize_WhisperDiarize.bundle").path
        let buildPath = "/Users/jacobwang/codebase/personal/process-audio/app/.build/arm64-apple-macosx/debug/WhisperDiarize_WhisperDiarize.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}