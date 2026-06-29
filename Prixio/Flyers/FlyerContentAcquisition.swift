import Foundation

/// How a banner's flyer content was obtained, chosen per destination from the
/// source shape discovery classified. Static shapes (`html`/`json`/`pdf`/`image`)
/// are processed in-app without a web view; only JS-rendered (`dynamicHTML`) or
/// `unknown` sources fall back to `renderedHTML`. See the strategy table in
/// `FlyerContentAcquisitionPlan.md`.
enum FlyerAcquisitionMethod: String, Equatable {
    case staticHTML
    case endpointJSON
    case endpointPDF
    case endpointImage
    case renderedHTML
    case imageOCR

    var label: String {
        switch self {
        case .staticHTML:
            "Static HTML"
        case .endpointJSON:
            "JSON endpoint"
        case .endpointPDF:
            "PDF endpoint"
        case .endpointImage:
            "Image endpoint"
        case .renderedHTML:
            "Rendered HTML"
        case .imageOCR:
            "Image + OCR"
        }
    }
}

/// The outcome of acquiring a banner's flyer content.
enum FlyerAcquisitionState: String, Equatable {
    /// Content carrying real price tokens (or a structured payload) — ready for
    /// extraction.
    case acquired
    /// Content was obtained but no prices were readable yet: a store-selection
    /// gate, empty flyer, anti-bot wall, or a binary asset awaiting OCR. The
    /// artifact is still returned so the gap is debuggable rather than silent.
    case acquiredNoPrices
    /// The connector is stubbed unsupported; no acquisition attempted.
    case unsupported
    /// The fetch or render failed.
    case failed

    var label: String {
        switch self {
        case .acquired:
            "Acquired"
        case .acquiredNoPrices:
            "No prices yet"
        case .unsupported:
            "Unsupported"
        case .failed:
            "Failed"
        }
    }
}

/// A stable, provenance-rich artifact handed from content acquisition to the
/// extraction phase. Acquisition decides *how to get bytes*; extraction decides
/// *how to turn bytes into `PriceCandidate`s*. Consistent with discovery's
/// logging discipline, the rendered payload is held transiently as bounded text
/// rather than persisted as a full artifact.
struct FlyerAcquiredContent: Identifiable, Equatable {
    let banner: FlyerBanner
    let state: FlyerAcquisitionState
    let acquisitionMethod: FlyerAcquisitionMethod?
    let sourceURL: URL?
    let finalURL: URL?
    /// Store id / postal code / region used when acquisition required one. `nil`
    /// means the default render with no store selected.
    let storeContext: String?
    let fetchedAt: Date?
    let payloadContentType: String?
    let payloadByteCount: Int
    /// Number of `$X.XX`-style tokens found in the rendered visible text — the
    /// honest signal of whether real flyer prices appeared.
    let priceTokenCount: Int
    /// Bounded sample of the rendered visible text, for debugging/review.
    let renderedTextSnippet: String?
    let message: String

    var id: FlyerBannerID { banner.id }

    init(
        banner: FlyerBanner,
        state: FlyerAcquisitionState,
        acquisitionMethod: FlyerAcquisitionMethod?,
        sourceURL: URL?,
        finalURL: URL?,
        storeContext: String? = nil,
        fetchedAt: Date? = nil,
        payloadContentType: String? = nil,
        payloadByteCount: Int = 0,
        priceTokenCount: Int = 0,
        renderedTextSnippet: String? = nil,
        message: String
    ) {
        self.banner = banner
        self.state = state
        self.acquisitionMethod = acquisitionMethod
        self.sourceURL = sourceURL
        self.finalURL = finalURL
        self.storeContext = storeContext
        self.fetchedAt = fetchedAt
        self.payloadContentType = payloadContentType
        self.payloadByteCount = payloadByteCount
        self.priceTokenCount = priceTokenCount
        self.renderedTextSnippet = renderedTextSnippet
        self.message = message
    }

    /// A banner whose connector is stubbed unsupported; no network/render work.
    static func unsupported(banner: FlyerBanner, reason: String) -> FlyerAcquiredContent {
        FlyerAcquiredContent(
            banner: banner,
            state: .unsupported,
            acquisitionMethod: nil,
            sourceURL: nil,
            finalURL: nil,
            message: reason
        )
    }

    /// A banner with no discovered source URL to acquire from.
    static func missingSource(banner: FlyerBanner) -> FlyerAcquiredContent {
        FlyerAcquiredContent(
            banner: banner,
            state: .failed,
            acquisitionMethod: nil,
            sourceURL: nil,
            finalURL: nil,
            message: "No discovered source URL to acquire flyer content from."
        )
    }
}

/// Acquires real flyer content for a banner from a discovered source URL. The
/// `sourceShape` discovery classified lets the implementation pick a per-destination
/// mechanism — process static HTML/JSON in-app, or render JS-only pages with a web
/// view. Callers depend only on this contract so acquisition stays testable with
/// fakes.
protocol FlyerContentAcquiring {
    func acquire(
        banner: FlyerBanner,
        from url: URL,
        sourceShape: FlyerSourceShape?,
        storeContext: String?
    ) async -> FlyerAcquiredContent
}

/// Console logging for the acquisition layer, mirroring `FlyerDiscoveryLogging` so a
/// device run produces a per-banner `[FlyerAcquisition]` trail (routing decision,
/// fetch/render details, price counts, escalation, errors) alongside the
/// `[FlyerDiscovery]` trail.
protocol FlyerAcquisitionLogging {
    func log(_ message: String)
}

struct ConsoleFlyerAcquisitionLogger: FlyerAcquisitionLogging {
    func log(_ message: String) {
        print("[FlyerAcquisition] \(message)")
    }
}

enum FlyerAcquisitionLogLabel {
    /// Same `rank-Banner_Name` shape as the discovery log, so lines correlate
    /// across the two trails.
    static func make(for banner: FlyerBanner) -> String {
        "\(banner.rank)-\(banner.name.replacingOccurrences(of: " ", with: "_"))"
    }
}
