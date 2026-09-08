import SwiftUI
import UIKit

/// Shared, current-Visit-only thumbnails for latest/following and similar taste.
/// The existing authorized full-screen reader remains the only album viewer.
struct PublicContentActivityMedia: View {
    let presentation: PublicContentMediaPresentation
    let restaurantName: String
    let tags: [String]
    let semanticID: String
    let photoAPI: (any PhotoBinaryAPI)?
    let onOpenRestaurant: () -> Void
    @State private var expanded = false
    @State private var showingPhotos = false
    @State private var selectedPhotoID: String?

    private var photos: [PublicContentPhotoV1] { presentation.galleryPhotos }
    private var visiblePhotos: [PublicContentPhotoV1] { expanded ? photos : Array(photos.prefix(9)) }

    var body: some View {
        VStack(alignment: .leading, spacing: TasteMapDesignTokens.Spacing.small) {
            if photos.isEmpty {
                Button(action: onOpenRestaurant) {
                    thumbnail(resolution: presentation.resolution, identity: semanticID)
                        .frame(width: TasteMapDesignTokens.Layout.socialFeedMediaWidth,
                               height: TasteMapDesignTokens.Layout.socialFeedMediaWidth)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看餐厅 \(restaurantName)")
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: TasteMapDesignTokens.Spacing.small),
                                         count: PublicContentMediaPresentation.columnCount(photoCount: photos.count)),
                          alignment: .leading, spacing: TasteMapDesignTokens.Spacing.small) {
                    ForEach(visiblePhotos) { photo in
                        Button {
                            selectedPhotoID = photo.photoId
                            showingPhotos = true
                        } label: {
                            Color.clear.aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    thumbnail(resolution: .init(sources: [.publicOrCachedPhoto(photo.photoId)]), identity: photo.photoId)
                                }
                                .clipped()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(restaurantName) 图片 \((photos.firstIndex(where: { $0.photoId == photo.photoId }) ?? 0) + 1) / \(photos.count)")
                        .accessibilityIdentifier("activity-photo-\(semanticID)-\(photo.photoId)")
                    }
                }
                .frame(maxWidth: photos.count == 1 ? TasteMapDesignTokens.Layout.socialFeedMediaWidth : .infinity, alignment: .leading)
                if photos.count > 9 && !expanded {
                    Button("查看全部 \(photos.count) 张照片") { expanded = true }
                        .font(TasteMapDesignTokens.Typography.control)
                        .frame(minHeight: TasteMapDesignTokens.Control.minimumHitTarget)
                        .accessibilityIdentifier("activity-photos-expand-\(semanticID)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("community-photos-\(semanticID)")
        .sheet(isPresented: $showingPhotos) {
            PublicContentPhotoGallery(photos: photos, photoAPI: photoAPI, initialPhotoID: selectedPhotoID)
        }
        .onChange(of: photos) { _, _ in showingPhotos = false; expanded = false }
        .onChange(of: semanticID) { _, _ in showingPhotos = false; expanded = false }
    }

    private func thumbnail(resolution: RestaurantImageResolution, identity: String) -> some View {
        TasteMapRestaurantImage(resolution: resolution, photoAPI: photoAPI, semanticID: identity,
                               categoryVisualID: FoodCategoryVisualResolver.resolve(name: restaurantName, tags: tags),
                               foodLibraryArtwork: .init(name: restaurantName, tags: tags,
                                                         categoryVisualID: FoodCategoryVisualResolver.resolve(name: restaurantName, tags: tags)),
                               accessibilityLabel: "\(restaurantName) 到访照片")
            .clipShape(RoundedRectangle(cornerRadius: TasteMapDesignTokens.Radius.compact, style: .continuous))
    }
}

/// Read-only counterpart of PhotoGalleryViewer for authorized public/friend
/// projections. Photo IDs never become local PhotoAssets or export payloads.
struct PublicContentPhotoGallery: View {
    let photos: [PublicContentPhotoV1]
    let photoAPI: (any PhotoBinaryAPI)?
    var initialPhotoID: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var selection = 0

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                    PublicContentGalleryPhoto(photo: photo, photoAPI: photoAPI)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .background(.black)
            .navigationTitle(photos.isEmpty ? "照片" : "\(selection + 1) / \(photos.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .accessibilityIdentifier("community-photo-gallery")
            .onAppear { selection = photos.firstIndex(where: { $0.photoId == initialPhotoID }) ?? 0 }
        }
    }
}

private struct PublicContentGalleryPhoto: View {
    let photo: PublicContentPhotoV1
    let photoAPI: (any PhotoBinaryAPI)?
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if failed {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                    Text("这张照片暂时无法查看")
                    Text("照片可能已删除或不再允许查看。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
                .accessibilityIdentifier("community-photo-unavailable-\(photo.photoId)")
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .task(id: photo.photoId) {
            image = nil
            failed = false
            guard let id = UUID(uuidString: photo.photoId), let photoAPI else {
                failed = true
                return
            }
            // Go through the authorized API, not the cross-card thumbnail
            // memory cache: revocation must not reveal a previous display image.
            do {
                let data = try await photoAPI.download(photoID: id, variant: .display)
                guard !Task.isCancelled else { return }
                image = UIImage(data: data)
                failed = image == nil
            } catch {
                guard !Task.isCancelled else { return }
                image = nil
                failed = true
            }
        }
        .onDisappear { image = nil }
        .accessibilityLabel("到访照片")
    }
}
