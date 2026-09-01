import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

nonisolated struct SharePosterBrandConfiguration: Equatable, Sendable {
    static let developmentURLKey = "TASTEMAP_SHARE_POSTER_DEV_URL"
    static let productionURLKey = "TASTEMAP_SHARE_POSTER_PROD_URL"

    let qrDestinationURL: URL?

    static func current(
        environment: TasteMapAppEnvironment = .current,
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) -> SharePosterBrandConfiguration {
        let key = environment == .development ? developmentURLKey : productionURLKey
        let rawValue = processInfo.environment[key]
            ?? (bundle.object(forInfoDictionaryKey: key) as? String)
        return resolve(environment: environment, rawValue: rawValue)
    }

    static func resolve(
        environment: TasteMapAppEnvironment,
        rawValue: String?
    ) -> SharePosterBrandConfiguration {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              !isForbiddenHost(host, environment: environment),
              let url = components.url else {
            return SharePosterBrandConfiguration(qrDestinationURL: nil)
        }
        return SharePosterBrandConfiguration(qrDestinationURL: url)
    }

    private static func isForbiddenHost(
        _ host: String,
        environment: TasteMapAppEnvironment
    ) -> Bool {
        if host == "localhost" || host == "127.0.0.1" || host == "::1" { return true }
        if host.hasSuffix(".workers.dev") || host == "workers.dev" { return true }
        if host == "testflight.apple.com" { return true }
        if environment == .production,
           host.hasPrefix("dev.") || host.contains("-dev.") {
            return true
        }
        return false
    }
}

nonisolated enum SharePosterQRCodeRenderer {
    static func image(for url: URL, scale: CGFloat = 12) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

struct SharePosterBrandFooter: View {
    let supportingText: String
    var tagline = "记录你的真实味觉地图"
    var configuration = SharePosterBrandConfiguration.current()

    var body: some View {
        HStack(spacing: 16) {
            SharePosterAppIcon(size: 58)
            VStack(alignment: .leading, spacing: 4) {
                Text("Taste Map")
                    .font(.system(size: 23, weight: .heavy, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.ink)
                Text(tagline)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.brand)
                Text(supportingText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(TasteMapAnalysisTheme.secondaryInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
            }
            Spacer(minLength: 14)
            if let url = configuration.qrDestinationURL,
               let image = SharePosterQRCodeRenderer.image(for: url) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(10)
                    .frame(width: 96, height: 96)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(TasteMapAnalysisTheme.ink.opacity(0.08), lineWidth: 1)
                    }
                    .accessibilityLabel("Taste Map 官方链接二维码")
                    .accessibilityIdentifier("share-poster-brand-qr")
            }
        }
        .accessibilityIdentifier("share-poster-brand-footer")
    }
}

private struct SharePosterAppIcon: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let image = currentAppIcon {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                FoodDiningVisualIcon(
                    kind: .genericDining,
                    usage: .decorative,
                    size: size,
                    foregroundColor: .white,
                    backgroundColor: TasteMapAnalysisTheme.brand,
                    accessibilityLabel: "Taste Map"
                )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
        .accessibilityIdentifier("share-poster-app-icon")
    }

    private var currentAppIcon: UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String] else {
            return UIImage(named: "AppIcon")
        }
        return files.reversed().compactMap(UIImage.init(named:)).first
            ?? UIImage(named: "AppIcon")
    }
}

#if DEBUG
#Preview("Brand Footer · QR configured") {
    SharePosterBrandFooter(
        supportingText: "仅基于你的真实记录生成",
        configuration: SharePosterBrandConfiguration(
            qrDestinationURL: URL(string: "https://example.com/taste-map")
        )
    )
    .padding(30)
    .background(TasteMapAnalysisTheme.canvas)
}

#Preview("Brand Footer · QR fail closed") {
    SharePosterBrandFooter(
        supportingText: "正式链接未配置时不生成二维码",
        configuration: SharePosterBrandConfiguration(qrDestinationURL: nil)
    )
    .padding(30)
    .background(TasteMapAnalysisTheme.canvas)
}
#endif
