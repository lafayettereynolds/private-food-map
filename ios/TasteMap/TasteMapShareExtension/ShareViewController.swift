import Social
import UniformTypeIdentifiers
import UIKit

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        statusLabel.text = "正在送到 Taste Map…"
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        Task { await captureSharedRestaurantClue() }
    }

    private func captureSharedRestaurantClue() async {
        do {
            let values = try await ShareInputReader.read(from: extensionContext?.inputItems ?? [])
            _ = try PendingRestaurantImportStore.live().enqueue(text: values.text, url: values.url)
            statusLabel.text = "已送到 Taste Map，打开 App 后确认餐厅。"
            try? await Task.sleep(for: .milliseconds(450))
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            statusLabel.text = "没有找到可识别的 HTTPS 链接或分享文字。"
            try? await Task.sleep(for: .milliseconds(800))
            extensionContext?.cancelRequest(withError: error)
        }
    }
}

private enum ShareInputReader {
    struct Values { let text: String?; let url: URL? }

    static func read(from items: [Any]) async throws -> Values {
        let attachments = items
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
        var url: URL?
        var text: String?
        for provider in attachments.prefix(8) {
            if url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let item = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier),
               let value = item as? URL {
                url = value
            }
            if text == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let item = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier),
               let value = item as? String {
                text = value
            }
        }
        guard url != nil || !(text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) else {
            throw PendingRestaurantImportStoreError.emptyPayload
        }
        return Values(text: text, url: url)
    }
}
