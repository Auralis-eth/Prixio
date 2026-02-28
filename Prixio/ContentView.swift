import Combine
import CoreLocation
import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    var body: some View {
        TabView {
            ScanRootView()
                .tabItem {
                    Label("Scan", systemImage: "viewfinder")
                }

            PlaceholderTabView(
                title: "Items",
                subtitle: "Saved entries and cheapest-price browsing land here next."
            )
            .tabItem {
                Label("Items", systemImage: "basket")
            }

            PlaceholderTabView(
                title: "Trends",
                subtitle: "Price history and trend charts can be layered onto the saved data model."
            )
            .tabItem {
                Label("Trends", systemImage: "chart.line.uptrend.xyaxis")
            }

            PlaceholderTabView(
                title: "Settings",
                subtitle: "Preferences, store management, and scanner defaults belong in this tab."
            )
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}

private struct ScanRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PriceEntry.createdAt, order: .reverse) private var entries: [PriceEntry]

    @StateObject private var sessionStore = ScanSessionStore()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var viewModel = ScanViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                scannerBackground

                VStack(spacing: 0) {
                    topHUD
                    Spacer()
                    bottomHUD
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                if viewModel.showToast {
                    VStack {
                        ToastView(text: "Price saved")
                        Spacer()
                    }
                    .padding(.top, 24)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .navigationBarHidden(true)
        }
        .task {
            viewModel.configureRecentItems(with: entries)
            try? PriceEntryRepository(context: modelContext).seedChainsIfNeeded()
            locationManager.requestWhenInUseAuthorization()
            await viewModel.loadNearbyStoresIfNeeded(
                sessionStore: sessionStore,
                location: locationManager.currentLocation
            )
        }
        .onChange(of: entries.count) { _, _ in
            viewModel.configureRecentItems(with: entries)
        }
        .onChange(of: locationManager.currentLocation) { _, location in
            Task {
                await viewModel.loadNearbyStoresIfNeeded(
                    sessionStore: sessionStore,
                    location: location
                )
            }
        }
        .sheet(isPresented: $viewModel.isShowingImagePicker) {
            CameraPicker(sourceType: viewModel.imagePickerSource) { image in
                Task {
                    await viewModel.handlePickedImage(
                        image,
                        sessionStore: sessionStore,
                        currentLocation: locationManager.currentLocation
                    )
                }
            }
        }
        .sheet(isPresented: $viewModel.isShowingConfirmationSheet) {
            ConfirmationSheet(
                draft: $viewModel.draft,
                capturedImage: viewModel.capturedImage,
                recentItems: viewModel.recentItems,
                onPriceCandidateTap: viewModel.applyPriceCandidate,
                onSelectSuggestion: viewModel.applyItemSuggestion,
                onOpenStoreSelection: { viewModel.isShowingStoreSheet = true },
                onRetake: {
                    viewModel.dismissConfirmationForRetake()
                    viewModel.openCamera()
                },
                onDiscard: viewModel.discardCapture,
                onSave: {
                    viewModel.save(context: modelContext)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewModel.isShowingStoreSheet) {
            StoreSelectionSheet(
                nearbyCandidates: sessionStore.nearbyCandidates,
                currentLocation: locationManager.currentLocation,
                selectedChainName: viewModel.draft.storeChainName,
                selectedLocationName: viewModel.draft.storeLocationName,
                onSelectCandidate: { candidate in
                    viewModel.applyStoreCandidate(candidate)
                    sessionStore.useLastStore(candidate)
                },
                onSelectChain: viewModel.applyChainSelection,
                onSearch: { query in
                    await viewModel.searchStores(
                        query: query,
                        currentLocation: locationManager.currentLocation
                    )
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var scannerBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.20, blue: 0.16),
                    Color(red: 0.06, green: 0.08, blue: 0.09),
                    Color(red: 0.14, green: 0.11, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if let image = viewModel.displayImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .overlay {
                        Rectangle()
                            .fill(.black.opacity(0.28))
                            .ignoresSafeArea()
                    }
            } else {
                ScannerGuideOverlay()
            }
        }
    }

    private var topHUD: some View {
        VStack(spacing: 14) {
            HStack {
                Spacer()
                Button(action: {
                    viewModel.isShowingStoreSheet = true
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.subheadline.weight(.semibold))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.storeChipTitle)
                                .font(.subheadline.weight(.semibold))
                            Text(viewModel.storeChipSubtitle)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.72))
                        }

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .accessibilityLabel("Detected store: \(viewModel.storeChipTitle), editable")
                Spacer()
            }

            Text("Point at the price tag.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.74))
        }
    }

    private var bottomHUD: some View {
        VStack(spacing: 16) {
            if viewModel.isProcessingOCR {
                ProgressView("Extracting details")
                    .tint(.white)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.4), in: Capsule())
            }

            HStack(alignment: .center) {
                Button(action: viewModel.toggleFlash) {
                    Image(systemName: viewModel.isFlashEnabled ? "bolt.fill" : "bolt.slash")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Flash toggle")

                Spacer()

                Button(action: viewModel.openCamera) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.22))
                            .frame(width: 84, height: 84)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 64, height: 64)
                    }
                }
                .accessibilityLabel("Shutter button")

                Spacer()

                Button(action: {
                    viewModel.openPhotoLibraryFallback()
                }) {
                    Group {
                        if let image = viewModel.capturedImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.16))
                                .overlay {
                                    Image(systemName: "photo")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.white)
                                }
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .accessibilityLabel("Gallery or last photo")
            }

            if let lastEntry = entries.first {
                HStack {
                    Text("Last save")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.64))

                    Spacer()

                    Text("\(lastEntry.itemNameRaw) • \(CurrencyFormatter.display(lastEntry.priceValue)) / \(lastEntry.unitType.displayName)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.84))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.black.opacity(0.28), in: Capsule())
            }
        }
    }
}

@MainActor
private final class ScanViewModel: ObservableObject {
    @Published var draft = PriceEntryDraft()
    @Published var isShowingImagePicker = false
    @Published var isShowingConfirmationSheet = false
    @Published var isShowingStoreSheet = false
    @Published var isProcessingOCR = false
    @Published var capturedImage: UIImage?
    @Published var previewImage: UIImage?
    @Published var isFlashEnabled = false
    @Published var showToast = false
    @Published var recentItems: [String] = []
    @Published var searchResults: [StoreCandidate] = []

    @Published var imagePickerSource: UIImagePickerController.SourceType = .camera

    private let ocrService = OCRService()
    private let storeService = StoreDetectionService()

    var displayImage: UIImage? {
        previewImage ?? capturedImage
    }

    var storeChipTitle: String {
        guard let candidate = candidatePreview else {
            return "Store unknown"
        }

        if let chainName = candidate.chainName {
            return chainName
        }

        return candidate.locationName
    }

    var storeChipSubtitle: String {
        guard let candidate = candidatePreview else {
            return "Tap to choose manually"
        }

        if let distanceMeters = candidate.distanceMeters {
            return "\(candidate.locationName) · \(DistanceFormatter.text(for: distanceMeters))"
        }

        return candidate.locationName
    }

    private var candidatePreview: StoreCandidate? {
        if !draft.storeLocationName.isEmpty || draft.storeChainName != nil {
            return StoreCandidate(
                id: UUID(),
                chainName: draft.storeChainName,
                locationName: draft.storeLocationName.isEmpty ? "Detected store" : draft.storeLocationName,
                address: draft.storeAddress,
                coordinate: draft.storeCoordinate,
                distanceMeters: nil,
                mapKitPlaceId: draft.storePlaceId
            )
        }
        return inferredStoreCandidate
    }

    private var inferredStoreCandidate: StoreCandidate?

    func configureRecentItems(with entries: [PriceEntry]) {
        recentItems = Array(
            entries
                .map(\.itemNameRaw)
                .filter { !$0.isEmpty }
                .reduce(into: [String]()) { result, name in
                    if !result.contains(name) {
                        result.append(name)
                    }
                }
                .prefix(6)
        )
    }

    func loadNearbyStoresIfNeeded(sessionStore: ScanSessionStore, location: CLLocation?) async {
        if let cached = sessionStore.cachedCandidatesIfFresh(), !cached.isEmpty {
            inferredStoreCandidate = cached.first
            applyInferredStore(from: cached.first)
            return
        }

        let stores = await storeService.fetchNearbyStores(location: location)
        sessionStore.updateCandidates(stores)
        inferredStoreCandidate = stores.first
        applyInferredStore(from: stores.first)
    }

    func searchStores(query: String, currentLocation: CLLocation?) async -> [StoreCandidate] {
        let results = await storeService.search(query: query, near: currentLocation)
        searchResults = results
        return results
    }

    func openCamera() {
        Haptics.impact()
        imagePickerSource = .camera
        isShowingImagePicker = true
    }

    func openPhotoLibraryFallback() {
        Haptics.impact()
        imagePickerSource = .photoLibrary
        isShowingImagePicker = true
    }

    func toggleFlash() {
        isFlashEnabled.toggle()
    }

    func handlePickedImage(
        _ image: UIImage?,
        sessionStore: ScanSessionStore,
        currentLocation: CLLocation?
    ) async {
        guard let image else {
            return
        }

        previewImage = image
        capturedImage = image
        draft = PriceEntryDraft(
            capturedAt: .now,
            imageData: image.jpegData(compressionQuality: 0.88)
        )
        isProcessingOCR = true
        isShowingConfirmationSheet = true

        let result = await ocrService.analyze(image: image)
        draft.ocrText = result.rawText
        draft.confidence = result.confidence
        draft.priceText = result.price.map(CurrencyFormatter.string) ?? ""
        draft.selectedUnit = result.unit
        draft.quantity = result.quantity
        draft.priceCandidates = Array(result.priceCandidates.prefix(2))
        draft.itemName = result.itemNameHint ?? ""

        if sessionStore.nearbyCandidates.isEmpty {
            let stores = await storeService.fetchNearbyStores(location: currentLocation)
            sessionStore.updateCandidates(stores)
        }

        let matchedCandidate = matchStoreCandidate(from: sessionStore.nearbyCandidates, ocrText: result.rawText)
        inferredStoreCandidate = matchedCandidate ?? sessionStore.lastStoreCandidate
        applyInferredStore(from: inferredStoreCandidate)
        isProcessingOCR = false
    }

    func applyPriceCandidate(_ candidate: PriceCandidate) {
        draft.priceText = CurrencyFormatter.string(candidate.value)
        draft.quantity = candidate.quantity
    }

    func applyItemSuggestion(_ suggestion: String) {
        draft.itemName = suggestion
    }

    func applyStoreCandidate(_ candidate: StoreCandidate) {
        draft.storeChainName = candidate.chainName ?? draft.storeChainName ?? "Unknown"
        draft.storeChainExplicitlySelected = true
        draft.storeLocationName = candidate.locationName
        draft.storeAddress = candidate.address ?? ""
        draft.storeCoordinate = candidate.coordinate
        draft.storePlaceId = candidate.mapKitPlaceId
        isShowingStoreSheet = false
    }

    func applyChainSelection(_ chainName: String) {
        draft.storeChainName = chainName
        draft.storeChainExplicitlySelected = true
    }

    func dismissConfirmationForRetake() {
        isShowingConfirmationSheet = false
        previewImage = nil
    }

    func discardCapture() {
        isShowingConfirmationSheet = false
        capturedImage = nil
        previewImage = nil
        draft = PriceEntryDraft()
    }

    func save(context: ModelContext) {
        guard draft.canSave else {
            return
        }

        do {
            try PriceEntryRepository(context: context).saveEntry(from: draft)
            Haptics.success()
            withAnimation(.easeOut(duration: 0.2)) {
                showToast = true
            }
            discardCapture()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                withAnimation(.easeIn(duration: 0.2)) {
                    self?.showToast = false
                }
            }
        } catch {
            isShowingConfirmationSheet = true
        }
    }

    private func applyInferredStore(from candidate: StoreCandidate?) {
        guard let candidate else {
            return
        }

        if draft.storeChainName == nil {
            draft.storeChainName = candidate.chainName
        }
        if draft.storeLocationName.isEmpty {
            draft.storeLocationName = candidate.locationName
        }
        if draft.storeAddress.isEmpty {
            draft.storeAddress = candidate.address ?? ""
        }
        if draft.storeCoordinate == nil {
            draft.storeCoordinate = candidate.coordinate
        }
        if draft.storePlaceId == nil {
            draft.storePlaceId = candidate.mapKitPlaceId
        }
        draft.storeChainExplicitlySelected = false
    }

    private func matchStoreCandidate(from candidates: [StoreCandidate], ocrText: String) -> StoreCandidate? {
        let inferredChain = StoreCatalog.inferredChain(from: ocrText)
        return candidates.first { candidate in
            candidate.chainName == inferredChain
        } ?? candidates.first
    }
}

private final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentLocation: CLLocation?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestWhenInUseAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.first
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    }
}

private struct ScannerGuideOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            let frameWidth = min(geometry.size.width - 48, 320)
            let frameHeight = frameWidth * 1.1

            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(.white.opacity(0.34), lineWidth: 2)
                    .frame(width: frameWidth, height: frameHeight)
                    .overlay(alignment: .topLeading) {
                        CornerBracket()
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 36, height: 36)
                            .padding(14)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        CornerBracket(rotation: .degrees(180))
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 36, height: 36)
                            .padding(14)
                    }

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .frame(width: frameWidth - 32, height: 120)
                    .overlay {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Yellow Onions")
                                .font(.title3.weight(.semibold))
                            Text("$3.99 / lb")
                                .font(.largeTitle.weight(.black))
                            Text("Aim the tag inside the frame, then tap the shutter.")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .foregroundStyle(.white)
                        .padding(18)
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct CornerBracket: Shape {
    var rotation: Angle = .zero

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path.applying(CGAffineTransform(rotationAngle: CGFloat(rotation.radians)))
    }
}

private struct ConfirmationSheet: View {
    @Binding var draft: PriceEntryDraft

    let capturedImage: UIImage?
    let recentItems: [String]
    let onPriceCandidateTap: (PriceCandidate) -> Void
    let onSelectSuggestion: (String) -> Void
    let onOpenStoreSelection: () -> Void
    let onRetake: () -> Void
    let onDiscard: () -> Void
    let onSave: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Group {
                        if let capturedImage {
                            Image(uiImage: capturedImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.gray.opacity(0.12))
                        }
                    }
                    .frame(width: 68, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Confirm details")
                            .font(.title3.weight(.semibold))
                        Text("Just now")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    fieldTitle("Item Name")
                    TextField("e.g., Yellow onions", text: $draft.itemName)
                        .textInputAutocapitalization(.words)
                        .textFieldStyle(.roundedBorder)

                    if !recentItems.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(recentItems, id: \.self) { item in
                                    Button(item) {
                                        onSelectSuggestion(item)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    fieldTitle("Price")
                    TextField("0.00", text: $draft.priceText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Price, editable")

                    if !draft.priceCandidates.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(draft.priceCandidates) { candidate in
                                Button(candidate.label) {
                                    onPriceCandidateTap(candidate)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.teal)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    fieldTitle("Unit")

                    Picker("Unit", selection: Binding(get: {
                        draft.selectedUnit ?? .each
                    }, set: { newValue in
                        draft.selectedUnit = newValue
                    })) {
                        Text("Each").tag(UnitType.each)
                        Text("lb").tag(UnitType.lb)
                        Text("kg").tag(UnitType.kg)
                    }
                    .pickerStyle(.segmented)
                    .overlay {
                        if draft.selectedUnit == nil {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.orange, lineWidth: 2)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    fieldTitle("Store Chain")

                    Menu {
                        ForEach(StoreCatalog.commonChains.map(\.name), id: \.self) { chain in
                            Button(chain) {
                                draft.storeChainName = chain
                                draft.storeChainExplicitlySelected = true
                            }
                        }
                    } label: {
                        HStack {
                            Text(draft.storeChainName ?? "Choose chain")
                                .foregroundStyle(draft.storeChainName == nil ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if !draft.storeChainExplicitlySelected {
                        Text("Confirm the detected store before saving.")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.orange)
                    }

                    fieldTitle("Store Location")

                    Button(action: onOpenStoreSelection) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(draft.storeLocationName.isEmpty ? "Choose branch or nearby store" : draft.storeLocationName)
                                    .foregroundStyle(draft.storeLocationName.isEmpty ? .secondary : .primary)
                                if !draft.storeAddress.isEmpty {
                                    Text(draft.storeAddress)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "location.magnifyingglass")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }

                HStack(spacing: 12) {
                    Button("Retake", action: onRetake)
                        .buttonStyle(.bordered)

                    Button("Discard", role: .destructive, action: onDiscard)
                        .buttonStyle(.bordered)

                    Spacer()

                    Button("Save", action: onSave)
                        .buttonStyle(.borderedProminent)
                        .disabled(!draft.canSave)
                }
            }
            .padding(20)
        }
    }

    private func fieldTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct StoreSelectionSheet: View {
    let nearbyCandidates: [StoreCandidate]
    let currentLocation: CLLocation?
    let selectedChainName: String?
    let selectedLocationName: String
    let onSelectCandidate: (StoreCandidate) -> Void
    let onSelectChain: (String) -> Void
    let onSearch: (String) async -> [StoreCandidate]

    @State private var query = ""
    @State private var searchResults: [StoreCandidate] = []

    var body: some View {
        NavigationStack {
            List {
                if !nearbyCandidates.isEmpty {
                    Section("Detected Nearby") {
                        ForEach(Array(nearbyCandidates.prefix(3))) { candidate in
                            Button {
                                onSelectCandidate(candidate)
                            } label: {
                                StoreCandidateRow(
                                    candidate: candidate,
                                    isSelected: candidate.locationName == selectedLocationName
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Choose Chain") {
                    ForEach(StoreCatalog.commonChains.map(\.name), id: \.self) { chain in
                        Button {
                            onSelectChain(chain)
                        } label: {
                            HStack {
                                Text(chain)
                                Spacer()
                                if selectedChainName == chain {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.teal)
                                }
                            }
                        }
                    }
                }

                Section("Search") {
                    TextField("Search stores", text: $query)
                        .textInputAutocapitalization(.words)
                        .onSubmit {
                            Task {
                                searchResults = await onSearch(query)
                            }
                        }

                    ForEach(searchResults) { candidate in
                        Button {
                            onSelectCandidate(candidate)
                        } label: {
                            StoreCandidateRow(
                                candidate: candidate,
                                isSelected: candidate.locationName == selectedLocationName
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Select Store")
        }
    }
}

private struct StoreCandidateRow: View {
    let candidate: StoreCandidate
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.chainName ?? "Unknown")
                    .font(.subheadline.weight(.semibold))
                Text(candidate.locationName)
                    .font(.callout)
                if let address = candidate.address {
                    Text(address)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                if let distanceMeters = candidate.distanceMeters {
                    Text(DistanceFormatter.text(for: distanceMeters))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.teal)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.65), in: Capsule())
    }
}

private struct PlaceholderTabView: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.93, blue: 0.88),
                    Color(red: 0.86, green: 0.91, blue: 0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Text(title)
                    .font(.largeTitle.bold())
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            .padding(32)
        }
    }
}

private enum CurrencyFormatter {
    static func string(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? ""
    }

    static func display(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CAD"
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}

private enum DistanceFormatter {
    static func text(for meters: CLLocationDistance) -> String {
        if meters < 1000 {
            return "\(Int(meters)) m"
        }

        return String(format: "%.1f km", meters / 1000)
    }
}

private enum Haptics {
    static func impact() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(sourceType) ? sourceType : .photoLibrary
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImagePicked: (UIImage?) -> Void

        init(onImagePicked: @escaping (UIImage?) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            picker.dismiss(animated: true)
            onImagePicked(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            onImagePicked(nil)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [PriceEntry.self, StoreChain.self, StoreLocation.self], inMemory: true)
}
