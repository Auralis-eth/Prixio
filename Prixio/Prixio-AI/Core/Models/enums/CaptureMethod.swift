import Foundation

/// How the price was captured
enum CaptureMethod: String, Sendable, CaseIterable, Codable {
    case manual = "manual"           // User typed it in
    case camera = "camera"           // Captured via camera
    case aiEnhanced = "ai_enhanced"  // AI-enhanced OCR
    case barcodeScan = "barcode"     // Scanned barcode
    case `import` = "import"           // Imported from external source
    case estimated = "estimated"     // Price estimation
}
