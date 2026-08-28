import SwiftUI

struct PresetProfileAvatarView: View {
    let preset: ProfileAvatarPreset

    var body: some View {
        GeometryReader { proxy in
            let cell = max(proxy.size.width, proxy.size.height)
            let position = preset.gridPosition
            Image("TasteMapAvatarPresets")
                .resizable()
                .frame(width: cell * 4, height: cell * 4)
                .offset(x: -CGFloat(position.column) * cell, y: -CGFloat(position.row) * cell)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .background(Color(uiColor: .secondarySystemBackground))
        .accessibilityHidden(true)
    }
}

struct ProfileAvatarView: View {
    let profile: UserProfile?
    let photo: PhotoAsset?

    var body: some View {
        Group {
            if let photo, photo.deletedAt == nil {
                PhotoAssetImageView(photo: photo, variant: .thumbnail)
            } else {
                PresetProfileAvatarView(preset: profile?.avatarPreset ?? .polarBear)
            }
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 3))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(profile.map { "\($0.displayName)的头像" } ?? "默认头像")
    }
}
