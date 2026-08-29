import SwiftUI
import UIKit

struct BackupExportShareSheet: UIViewControllerRepresentable {
    let fileURL: URL
    let onCompletion: (Bool, Error?) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [fileURL],
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, completed, _, error in
            Task { @MainActor in onCompletion(completed, error) }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
