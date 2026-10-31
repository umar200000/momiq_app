import Foundation
import Vision

// Read the actual simulator pixels. The role choices and continue button
// distinguish the first interactive Flutter screen from the launch image.
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
let image = URL(fileURLWithPath: CommandLine.arguments[1])
try VNImageRequestHandler(url: image, options: [:]).perform([request])
let words = (request.results ?? []).compactMap {
    $0.topCandidates(1).first?.string.lowercased()
}.joined(separator: " ")
let labels = ["mijozman", "enagaman", "davom etish"]
let found = labels.filter { words.contains($0) }
print("Role screen labels: \(found.joined(separator: ", "))")
exit(found.count == labels.count ? 0 : 1)
