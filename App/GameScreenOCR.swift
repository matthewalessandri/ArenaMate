import AppKit
import Foundation
import CoreGraphics
import ScreenCaptureKit
import Vision

/// Uses ScreenCaptureKit to capture only the Hearthstone window; never the
/// desktop, private browser windows, microphone, or other applications.
@MainActor
enum GameScreenOCR {
    struct Capture {
        var names: [String]?
        var detectedClass: String?
        var message: String
        var windowName: String
        var recognizedLines: [RecognizedLine]
        var matchedNames: [String]
    }

    enum ScanError: LocalizedError {
        case windowNotFound(String)
        case noImage
        case permissionDenied
        var errorDescription: String? {
            switch self {
            case .windowNotFound(let apps):
                return "Hearthstone window not found. Apps: \(apps). Try Borderless mode if exclusive Fullscreen hides the window."
            case .noImage: return "ScreenCaptureKit did not return a picture. Check Screen Recording permission."
            case .permissionDenied: return "This ArenaMate build is not authorized for Screen Recording."
            }
        }
    }

    private static var lastImage: CGImage?
    private static var lastCapture: Capture?

    static func scan(catalog: CatalogIndex, playerClass: String) async throws -> Capture {
        // Defense in depth: no ScreenCaptureKit calls without current TCC access.
        // CGPreflight does not itself request access or show a permission dialog.
        guard CGPreflightScreenCaptureAccess() else { throw ScanError.permissionDenied }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let games = content.windows.filter { window in
            let owner = window.owningApplication?.applicationName.lowercased() ?? ""
            let title = window.title?.lowercased() ?? ""
            return (owner.contains("hearthstone") || title.contains("hearthstone"))
                && window.frame.width > 500 && window.frame.height > 320
        }
        guard let game = games.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            let apps = Array(Set(content.windows.compactMap { $0.owningApplication?.applicationName }))
                .sorted().prefix(8).joined(separator: ", ")
            throw ScanError.windowNotFound(apps)
        }
        let filter = SCContentFilter(desktopIndependentWindow: game)
        let config = SCStreamConfiguration()
        let scale = min(2.0, 2500.0 / max(1, game.frame.width), 1800.0 / max(1, game.frame.height))
        config.width = max(1, Int(game.frame.width * scale))
        config.height = max(1, Int(game.frame.height * scale))
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        lastImage = image
        // Vision and catalog matching are CPU work; keep them off the UI actor.
        let result = try await Task.detached(priority: .userInitiated) {
            try recognize(image: image, catalog: catalog, playerClass: "ALL")
        }.value
        let detectedClass = HeroClassRecognition.detect(lines: result.lines, offeredNames: result.names, catalog: catalog)
        let report = Capture(names: result.names, detectedClass: detectedClass, message: result.message,
                             windowName: "\(game.owningApplication?.applicationName ?? "Hearthstone") · \(config.width)x\(config.height)",
                             recognizedLines: result.lines, matchedNames: result.matchedNames)
        lastCapture = report
        return report
    }

    static func scanScreenshot(at url: URL, catalog: CatalogIndex, playerClass: String) throws -> Capture {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw ScanError.noImage }
        lastImage = cgImage
        let result = try recognize(image: cgImage, catalog: catalog, playerClass: "ALL")
        let detectedClass = HeroClassRecognition.detect(lines: result.lines, offeredNames: result.names, catalog: catalog)
        let report = Capture(names: result.names, detectedClass: detectedClass, message: result.message,
                             windowName: "Imported screenshot · \(cgImage.width)x\(cgImage.height)",
                             recognizedLines: result.lines, matchedNames: result.matchedNames)
        lastCapture = report
        return report
    }

    nonisolated private static func recognize(image: CGImage, catalog: CatalogIndex, playerClass: String)
        throws -> (names: [String]?, message: String, lines: [RecognizedLine], matchedNames: [String]) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false // Fantasy card names should not be autocorrected.
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = 0.009
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let observations = request.results ?? []
        let lines: [RecognizedLine] = observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first else { return nil }
            return RecognizedLine(text: text.string, x: Double(observation.boundingBox.midX),
                                  y: Double(observation.boundingBox.midY), confidence: Double(text.confidence))
        }
        // Include Vision's alternative interpretations when matching fantasy names,
        // while keeping the diagnostic text restricted to its top predictions.
        let alternatives: [RecognizedLine] = observations.flatMap { observation in
            observation.topCandidates(3).map { candidate in
                RecognizedLine(text: candidate.string, x: Double(observation.boundingBox.midX),
                               y: Double(observation.boundingBox.midY), confidence: Double(candidate.confidence))
            }
        }
        var offered = OfferRecognition.findOffer(lines: alternatives, catalog: catalog, playerClass: playerClass)
        if offered.names == nil {
            // Vision can split a long name like "Husk, Eternal Reaper" into two
            // vertically neighboring text boxes. Only join close boxes, then let
            // the card catalog validate the result before displaying any pick.
            var combined = alternatives
            let primary = Array(lines.prefix(90))
            for i in primary.indices {
                for j in primary.indices where i != j {
                    let upper = primary[i], lower = primary[j]
                    let separation = upper.y - lower.y
                    guard separation >= 0.012, separation <= 0.070,
                          abs(upper.x - lower.x) < 0.072,
                          upper.y < 0.82, lower.y > 0.28 else { continue }
                    combined.append(RecognizedLine(text: upper.text + " " + lower.text,
                                                 x: (upper.x + lower.x) / 2,
                                                 y: (upper.y + lower.y) / 2,
                                                 confidence: min(upper.confidence, lower.confidence)))
                }
            }
            let stitched = OfferRecognition.findOffer(lines: combined, catalog: catalog, playerClass: playerClass)
            if stitched.names != nil { offered = stitched }
        }
        let message = offered.message + " (\(lines.count) OCR text lines)"
        return (offered.names, message, lines, offered.matched)
    }

    static func diagnosticText() -> String? {
        guard let report = lastCapture else { return nil }
        let header = "ArenaMate screen recognition diagnostic\nWindow: \(report.windowName)\nResult: \(report.message)\nMatched: \(report.matchedNames.joined(separator: " | "))\n\nAll OCR lines (text / x / y / confidence):\n"
        let body = report.recognizedLines.map {
            "\($0.text) / \(String(format: "%.3f", $0.x)) / \(String(format: "%.3f", $0.y)) / \(String(format: "%.2f", $0.confidence))"
        }.joined(separator: "\n")
        return header + body + "\n"
    }

    /// User-initiated diagnostic: writes only the last Hearthstone window frame
    /// and the OCR output locally. No uploads or telemetry.
    static func saveDiagnostic() throws -> URL {
        guard let image = lastImage, let report = lastCapture else { throw ScanError.noImage }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ArenaMate/Diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let folder = root.appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        guard let png else { throw ScanError.noImage }
        try png.write(to: folder.appendingPathComponent("hearthstone-window.png"), options: .atomic)
        guard let text = diagnosticText() else { throw ScanError.noImage }
        try text.write(to: folder.appendingPathComponent("recognition.txt"), atomically: true, encoding: .utf8)
        return folder
    }
}
