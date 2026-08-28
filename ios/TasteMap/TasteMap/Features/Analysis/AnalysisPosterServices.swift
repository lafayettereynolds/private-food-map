import Photos
import SwiftUI
import UIKit

enum AnalysisPosterRenderError: LocalizedError, Equatable {
    case imageUnavailable
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .imageUnavailable: "分享海报生成失败，请重试。"
        case .pngEncodingFailed: "分享图片暂时无法导出，请重试。"
        }
    }
}

@MainActor
enum AnalysisPosterRenderer {
    static func render(
        report: TasteProfileAnalysis,
        resolvedImages: [UUID: UIImage] = [:]
    ) throws -> UIImage {
        let renderer = ImageRenderer(
            content: AnalysisPosterView(report: report, resolvedImages: resolvedImages)
        )
        renderer.proposedSize = ProposedViewSize(AnalysisPosterView.canvasSize)
        renderer.scale = 1
        renderer.isOpaque = true
        guard let image = renderer.uiImage else { throw AnalysisPosterRenderError.imageUnavailable }
        return image
    }
}

@MainActor
enum AnalysisPosterImageResolver {
    static func resolve(
        report: TasteProfileAnalysis,
        photosByID: [UUID: PhotoAsset],
        coordinator: PhotoTransferCoordinator?
    ) async -> [UUID: UIImage] {
        guard let coordinator else { return [:] }
        let references = report.hero.imageReferences + report.restaurants.map(\.imageReference)
        var seen = Set<UUID>()
        let ids = references.compactMap { reference -> UUID? in
            guard case .photo(let id) = reference, seen.insert(id).inserted else { return nil }
            return id
        }
        var result: [UUID: UIImage] = [:]
        for id in ids {
            guard let photo = photosByID[id] else { continue }
            if let data = try? await coordinator.imageData(for: photo, variant: .display),
               let image = UIImage(data: data) {
                result[id] = image
            }
        }
        return result
    }
}

struct AnalysisPosterTemporaryFileStore: Sendable {
    let rootURL: URL

    init(rootURL: URL = FileManager.default.temporaryDirectory) {
        self.rootURL = rootURL.appendingPathComponent("TasteMapAnalysisPosters", isDirectory: true)
    }

    func write(_ image: UIImage, id: String) throws -> URL {
        guard let data = image.pngData() else { throw AnalysisPosterRenderError.pngEncodingFailed }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let safeID = id.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "-", options: .regularExpression)
        let url = rootURL.appendingPathComponent("taste-map-\(safeID)-\(UUID().uuidString).png")
        try data.write(to: url, options: .atomic)
        return url
    }

    func remove(_ url: URL) {
        guard url.deletingLastPathComponent().standardizedFileURL == rootURL.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

enum AnalysisPosterSaveError: LocalizedError, Equatable {
    case permissionDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "未获得添加照片权限。你可以在系统设置中允许 Taste Map 添加照片。"
        case .saveFailed: "图片没有保存成功，请稍后重试。"
        }
    }
}

@MainActor
struct AnalysisPosterPhotoSaver {
    let authorizationStatus: () -> PHAuthorizationStatus
    let requestAuthorization: () async -> PHAuthorizationStatus
    let performSave: (UIImage) async throws -> Void

    init(
        authorizationStatus: @escaping () -> PHAuthorizationStatus,
        requestAuthorization: @escaping () async -> PHAuthorizationStatus,
        performSave: @escaping (UIImage) async throws -> Void
    ) {
        self.authorizationStatus = authorizationStatus
        self.requestAuthorization = requestAuthorization
        self.performSave = performSave
    }

    static let live = AnalysisPosterPhotoSaver(
        authorizationStatus: { PHPhotoLibrary.authorizationStatus(for: .addOnly) },
        requestAuthorization: { await PHPhotoLibrary.requestAuthorization(for: .addOnly) },
        performSave: { image in
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        }
    )

    func save(_ image: UIImage) async throws {
        var status = authorizationStatus()
        if status == .notDetermined { status = await requestAuthorization() }
        guard status == .authorized || status == .limited else {
            throw AnalysisPosterSaveError.permissionDenied
        }
        do {
            try await performSave(image)
        } catch {
            throw AnalysisPosterSaveError.saveFailed
        }
    }
}

struct AnalysisPosterSheet: View {
    let report: TasteProfileAnalysis
    let photosByID: [UUID: PhotoAsset]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.photoTransferCoordinator) private var photoTransferCoordinator
    @State private var posterImage: UIImage?
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var shareFile: ShareFile?
    @State private var isSaving = false

    private let temporaryFiles = AnalysisPosterTemporaryFileStore()

    var body: some View {
        NavigationStack {
            ZStack {
                TasteMapAnalysisTheme.canvas.ignoresSafeArea()
                content
            }
            .navigationTitle("分享海报")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task(id: report.id) { await generatePoster() }
            .sheet(item: $shareFile) { file in
                SystemActivityView(items: [file.url]) {
                    temporaryFiles.remove(file.url)
                    shareFile = nil
                }
            }
            .alert("Taste Map", isPresented: Binding(
                get: { statusMessage != nil },
                set: { if !$0 { statusMessage = nil } }
            )) {
                Button("好") { statusMessage = nil }
            } message: {
                Text(statusMessage ?? "")
            }
            .onDisappear {
                if let shareFile { temporaryFiles.remove(shareFile.url) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let posterImage {
            VStack(spacing: 16) {
                ScrollView {
                    Image(uiImage: posterImage)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: TasteMapAnalysisTheme.brandDeep.opacity(0.15), radius: 18, y: 9)
                        .padding(.horizontal, 20)
                        .padding(.top, 18)
                        .accessibilityIdentifier("analysis-poster-preview")
                }

                HStack(spacing: 12) {
                    Button { Task { await saveImage(posterImage) } } label: {
                        Label(isSaving ? "保存中" : "保存图片", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaving)
                    .accessibilityIdentifier("analysis-poster-save")

                    Button { share(posterImage) } label: {
                        Label("系统分享", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TasteMapAnalysisTheme.brand)
                    .accessibilityIdentifier("analysis-poster-system-share")
                }
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        } else if let errorMessage {
            ContentUnavailableView {
                Label("海报没有生成", systemImage: "photo.badge.exclamationmark")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("重试") { Task { await generatePoster() } }
            }
        } else {
            VStack(spacing: 14) {
                ProgressView().controlSize(.large).tint(TasteMapAnalysisTheme.brand)
                Text("正在把味觉地图排成海报…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
            }
        }
    }

    @MainActor
    private func generatePoster() async {
        posterImage = nil
        errorMessage = nil
        let images = await AnalysisPosterImageResolver.resolve(
            report: report,
            photosByID: photosByID,
            coordinator: photoTransferCoordinator
        )
        do {
            posterImage = try AnalysisPosterRenderer.render(report: report, resolvedImages: images)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func saveImage(_ image: UIImage) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await AnalysisPosterPhotoSaver.live.save(image)
            statusMessage = "分享海报已保存到照片。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func share(_ image: UIImage) {
        do {
            shareFile = ShareFile(url: try temporaryFiles.write(image, id: report.id))
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

private struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct SystemActivityView: UIViewControllerRepresentable {
    let items: [Any]
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onComplete() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
