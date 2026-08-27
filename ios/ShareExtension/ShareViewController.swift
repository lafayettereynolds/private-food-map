import Social
import UniformTypeIdentifiers
import UIKit

final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        statusLabel.text = "正在识别餐厅链接…"
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 2
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
        ])
        Task { await captureSharedRestaurant() }
    }

    @MainActor
    private func captureSharedRestaurant() async {
        do {
            let shared = try await firstSupportedItem()
            let store = try PendingExternalRestaurantImportStore()
            let ownerSubject = UserDefaults(suiteName: appGroupIdentifier)?.string(forKey: "taste-map.current-user-subject")
            let pending = try store.enqueue(source: shared.source, payload: shared.payload, ownerSubject: ownerSubject)
            guard let deepLink = URL(string: "tastemap://external-import/\(pending.id.uuidString)") else {
                throw ShareExtensionError.invalidDeepLink
            }
            statusLabel.text = "已交给 Taste Map"
            extensionContext?.open(deepLink) { [weak self] _ in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        } catch {
            statusLabel.text = "无法识别这个分享内容，请复制链接后在 Taste Map 中粘贴。"
            try? await Task.sleep(for: .seconds(1.2))
            extensionContext?.cancelRequest(withError: error)
        }
    }

    private var appGroupIdentifier: String {
        Bundle.main.object(forInfoDictionaryKey: "TasteMapAppGroupIdentifier") as? String ?? ""
    }

    private func firstSupportedItem() async throws -> (source: ExternalRestaurantImportSource, payload: String) {
        let providers = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] } ?? []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                return (.url, url.absoluteString)
            }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                return (.sharedText, text)
            }
        }
        throw ShareExtensionError.unsupportedContent
    }
}

private enum ShareExtensionError: LocalizedError {
    case unsupportedContent
    case invalidDeepLink
}
