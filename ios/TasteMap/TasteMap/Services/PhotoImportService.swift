import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct PreparedLocalPhoto: Identifiable, Sendable {
    let id: UUID
    let originalFileRelativePath: String
    let displayFileRelativePath: String
    let thumbnailFileRelativePath: String
    let originalMimeType: String
    let displayMimeType: String
    let originalByteSize: Int64
    let displayByteSize: Int64
    let width: Int
    let height: Int
    let displayContentHash: String
    let thumbnailContentHash: String
    let originalFileName: String?

    var allRelativePaths: [String] {
        [originalFileRelativePath, displayFileRelativePath, thumbnailFileRelativePath]
    }
}

nonisolated enum PhotoImportError: LocalizedError, Equatable {
    case invalidImage
    case unsupportedImage
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: "这张图片无法读取，请换一张重试。"
        case .unsupportedImage: "暂不支持这张图片的格式。"
        case .encodingFailed: "图片处理失败，请重试。"
        }
    }
}

actor PhotoImportService {
    // Technical ceiling. Free/Premium product limits are resolved centrally.
    static let maximumSelectionCount = 20
    static let maximumDisplayPixel = 2_048
    static let maximumThumbnailPixel = 480

    private let files: any LocalPhotoFileStoring

    init(files: any LocalPhotoFileStoring) {
        self.files = files
    }

    func prepare(
        data: Data,
        suggestedContentType: String? = nil,
        originalFileName: String? = nil,
        photoID: UUID = UUID()
    ) async throws -> PreparedLocalPhoto {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw PhotoImportError.invalidImage
        }
        let display = try renderedJPEG(
            source: source,
            maximumPixel: Self.maximumDisplayPixel,
            quality: 0.84
        )
        let thumbnail = try renderedJPEG(
            source: source,
            maximumPixel: Self.maximumThumbnailPixel,
            quality: 0.76
        )
        let detectedMimeType = mimeType(source: source, suggested: suggestedContentType)
        let original: (data: Data, mimeType: String)
        if LocalPhotoFileStore.supports(mimeType: detectedMimeType) {
            original = (data, detectedMimeType)
        } else {
            original = (display.data, "image/jpeg")
        }

        var paths: [String] = []
        do {
            let originalPath = try await files.save(
                original.data,
                photoID: photoID,
                mimeType: original.mimeType,
                variant: .original
            )
            paths.append(originalPath)
            let displayPath = try await files.save(
                display.data,
                photoID: photoID,
                mimeType: "image/jpeg",
                variant: .display
            )
            paths.append(displayPath)
            let thumbnailPath = try await files.save(
                thumbnail.data,
                photoID: photoID,
                mimeType: "image/jpeg",
                variant: .thumbnail
            )
            paths.append(thumbnailPath)
            return PreparedLocalPhoto(
                id: photoID,
                originalFileRelativePath: originalPath,
                displayFileRelativePath: displayPath,
                thumbnailFileRelativePath: thumbnailPath,
                originalMimeType: original.mimeType,
                displayMimeType: "image/jpeg",
                originalByteSize: Int64(original.data.count),
                displayByteSize: Int64(display.data.count),
                width: display.width,
                height: display.height,
                displayContentHash: Self.sha256(display.data),
                thumbnailContentHash: Self.sha256(thumbnail.data),
                originalFileName: originalFileName
            )
        } catch {
            for path in paths { try? await files.delete(relativePath: path) }
            throw error
        }
    }

    func discard(_ prepared: PreparedLocalPhoto) async {
        for path in prepared.allRelativePaths {
            try? await files.delete(relativePath: path)
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func renderedJPEG(
        source: CGImageSource,
        maximumPixel: Int,
        quality: Double
    ) throws -> (data: Data, width: Int, height: Int) {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PhotoImportError.invalidImage
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { throw PhotoImportError.encodingFailed }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { throw PhotoImportError.encodingFailed }
        return (output as Data, image.width, image.height)
    }

    private func mimeType(source: CGImageSource, suggested: String?) -> String {
        if let suggested = suggested?.lowercased(), suggested.hasPrefix("image/") {
            return suggested
        }
        guard let type = CGImageSourceGetType(source) else { return "image/jpeg" }
        return UTType(type as String)?.preferredMIMEType ?? "image/jpeg"
    }
}
