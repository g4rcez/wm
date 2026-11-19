import Core
import CoreGraphics
import Vision

/// Reads the words of a picture of the screen with the Vision framework, for the windows that give no text to the
/// Accessibility API (a terminal that draws its own text, a canvas).
public enum TextRecognizer {
    /// The words of some windows. `image` is a picture of the whole `display` (a frame in screen coordinates), and each window
    /// is the part of it that shows, with its index for `TextWord.window`. The windows are read at the same time.
    public static func words(in image: CGImage, display: CGRect, windows: [(index: Int, frame: CGRect)]) async -> [TextWord] {
        await withTaskGroup(of: [TextWord].self) { group in
            for window in windows {
                group.addTask { words(in: image, display: display, window: window.frame, index: window.index) }
            }
            return await group.reduce(into: []) { $0 += $1 }
        }
    }

    private static func words(in image: CGImage, display: CGRect, window: CGRect, index: Int) -> [TextWord] {
        // The picture is in pixels and the frames are in points.
        let scale = CGFloat(image.width) / display.width
        let part = CGRect(
            x: (window.minX - display.minX) * scale, y: (window.minY - display.minY) * scale, width: window.width * scale,
            height: window.height * scale)
        guard display.width > 0, let crop = image.cropping(to: part.integral) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // The correction changes code and names into words of a dictionary.
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        guard (try? VNImageRequestHandler(cgImage: crop).perform([request])) != nil else { return [] }
        var words: [TextWord] = []
        for observation in request.results ?? [] {
            guard let line = observation.topCandidates(1).first else { continue }
            for word in line.string.split(whereSeparator: \.isWhitespace) {
                guard let box = try? line.boundingBox(for: word.startIndex..<word.endIndex) else { continue }
                let frame = TextPage.screenRect(normalized: box.boundingBox, in: window)
                words.append(TextWord(String(word), frame: frame, window: index, source: .ocr))
            }
        }
        return words
    }
}
