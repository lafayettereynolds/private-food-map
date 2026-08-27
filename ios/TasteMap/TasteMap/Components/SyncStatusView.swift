import SwiftUI

struct SyncStatusView: View {
    let presentation: SyncPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon

            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(presentation.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sync-status-\(presentation.phase.rawValue)")
    }

    @ViewBuilder
    private var statusIcon: some View {
        if presentation.phase == .syncing {
            ProgressView()
                .controlSize(.small)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
        } else {
            Image(systemName: presentation.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
        }
    }

    private var iconColor: Color {
        switch presentation.phase {
        case .synced: .green
        case .pending, .waitingForNetwork: .orange
        case .failed: .red
        case .conflicted: .purple
        case .signedOut, .syncing: .accentColor
        }
    }
}
