import SwiftUI
import UIKit

struct PhotoAssetImageView: View {
    let photo: PhotoAsset
    var variant: PhotoBinaryVariant = .thumbnail
    var contentMode: ContentMode = .fill

    @Environment(\.photoTransferCoordinator) private var coordinator
    @State private var image: UIImage?
    @State private var failed = false
    @State private var previewPlaceholder = false

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if previewPlaceholder {
                ZStack {
                    LinearGradient(
                        colors: [.orange.opacity(0.55), .pink.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "fork.knife")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
            } else if failed {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .clipped()
        .task(id: cacheIdentity) {
            guard let coordinator else {
                previewPlaceholder = true
                return
            }
            do {
                let data = try await coordinator.imageData(for: photo, variant: variant)
                image = UIImage(data: data)
                failed = image == nil
            } catch {
                failed = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("到访照片")
    }

    private var cacheIdentity: String {
        "\(photo.id.uuidString)-\(variant.rawValue)-\(photo.storageKey ?? "local")-\(photo.updatedAt.timeIntervalSince1970)"
    }
}

struct PreparedPhotoImageView: View {
    let prepared: PreparedLocalPhoto

    @Environment(\.photoTransferCoordinator) private var coordinator
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
            }
        }
        .clipped()
        .task(id: prepared.id) {
            guard let coordinator,
                  let data = try? await coordinator.localData(
                    relativePath: prepared.thumbnailFileRelativePath
                  ) else { return }
            image = UIImage(data: data)
        }
        .accessibilityLabel("待保存照片")
    }
}

struct PhotoUploadStatusBadge: View {
    let photo: PhotoAsset

    var body: some View {
        Group {
            switch photo.uploadState {
            case .localOnly, .queued:
                Label("等待上传", systemImage: "clock.fill")
            case .uploading:
                Label("上传中", systemImage: "arrow.up.circle.fill")
            case .uploaded:
                Label("已上传", systemImage: "checkmark.circle.fill")
            case .failed:
                Label("上传失败", systemImage: "exclamationmark.circle.fill")
            case .deleted:
                Label("已删除", systemImage: "trash.fill")
            }
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .foregroundStyle(.white)
        .background(statusColor.opacity(0.9), in: Capsule())
    }

    private var statusColor: Color {
        switch photo.uploadState {
        case .failed: .red
        case .uploaded: .green
        case .uploading: .blue
        case .localOnly, .queued: .orange
        case .deleted: .secondary
        }
    }
}

struct PhotoGalleryViewer: View {
    let photos: [PhotoAsset]
    @State private var selection: UUID
    @Environment(\.dismiss) private var dismiss

    init(photos: [PhotoAsset], selectedID: UUID) {
        self.photos = photos
        _selection = State(initialValue: selectedID)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(photos) { photo in
                    PhotoAssetImageView(photo: photo, variant: .display, contentMode: .fit)
                        .background(.black)
                        .tag(photo.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .background(.black)
            .navigationTitle(positionText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var positionText: String {
        guard let index = photos.firstIndex(where: { $0.id == selection }) else { return "照片" }
        return "\(index + 1) / \(photos.count)"
    }
}
