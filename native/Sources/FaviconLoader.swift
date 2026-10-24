import AppKit
import Foundation
import ImageIO

/// Public icon requests use no website cookies, credentials, or third-party icon service.
@MainActor final class FaviconLoader {
    static let shared = FaviconLoader()
    private let images = NSCache<NSString, NSImage>()
    private let failures = NSCache<NSString, NSDate>()
    private var pending: [String: Task<NSImage?, Never>] = [:]
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 6; config.timeoutIntervalForResource = 12
        session = URLSession(configuration: config)
        images.countLimit = 256; images.totalCostLimit = 8 * 1024 * 1024
        failures.countLimit = 256
    }
    private static func webURL(_ url: URL?) -> URL? {
        guard let url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: true),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""), parts.host != nil else { return nil }
        parts.user = nil; parts.password = nil; parts.fragment = nil
        return parts.url
    }
    func image(for value: String) async -> NSImage? {
        guard let page = Self.webURL(URL(string: value)), var origin = URLComponents(url: page, resolvingAgainstBaseURL: true) else { return nil }
        origin.path = "/"; origin.query = nil
        guard let root = origin.url else { return nil }
        let key = root.absoluteString
        if let image = images.object(forKey: key as NSString) { return image }
        if let retry = failures.object(forKey: key as NSString), retry.timeIntervalSinceNow > 0 { return nil }
        if let task = pending[key] { return await task.value }
        let task = Task { await self.load(page: page, root: root) }
        pending[key] = task
        let image = await task.value; pending[key] = nil
        if let image { images.setObject(image, forKey: key as NSString, cost: Int(image.size.width * image.size.height) * 4) }
        else { failures.setObject(NSDate(timeIntervalSinceNow: 60), forKey: key as NSString) }
        return image
    }
    private func load(page: URL, root: URL) async -> NSImage? {
        let conventional = root.appendingPathComponent("favicon.ico")
        if let image = await icon(conventional) { return image }
        guard let (data, response) = await resource(page, limit: 256 * 1024, headOnly: true),
              response.mimeType?.lowercased().contains("html") == true else { return nil }
        for url in Self.candidates(in: data, base: response.url ?? page).prefix(4) where url != conventional {
            if let image = await icon(url) { return image }
        }
        return nil
    }
    private func icon(_ url: URL) async -> NSImage? {
        guard let (data, _) = await resource(url, limit: 1024 * 1024, headOnly: false),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 64, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
    private func resource(_ url: URL, limit: Int, headOnly: Bool) async -> (Data, HTTPURLResponse)? {
        do {
            var request = URLRequest(url: url)
            request.setValue(headOnly ? "text/html" : "image/*", forHTTPHeaderField: "Accept")
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), Self.webURL(response.url) != nil else { return nil }
            var data = Data()
            for try await byte in bytes {
                if data.count >= limit { return headOnly ? (data, response) : nil }
                data.append(byte)
                if headOnly, byte == 62, String(decoding: data.suffix(7), as: UTF8.self).lowercased() == "</head>" { break }
            }
            return (data, response)
        } catch { return nil }
    }
    static func candidates(in data: Data, base: URL) -> [URL] {
        // Tidy HTML parses declarations without executing scripts or loading subresources.
        guard let document = try? XMLDocument(data: data, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]) else { return [] }
        let baseURL = (try? document.nodes(forXPath: "//base[@href]").first as? XMLElement).flatMap { $0.attribute(forName: "href")?.stringValue }.flatMap { webURL(URL(string: $0, relativeTo: base)?.absoluteURL) } ?? base
        let links = (try? document.nodes(forXPath: "//link[@href]")) ?? []
        var candidates: [(URL, Int)] = []
        for case let link as XMLElement in links {
            let rel = (link.attribute(forName: "rel")?.stringValue ?? "").lowercased().split(whereSeparator: { $0.isWhitespace })
            guard rel.contains("icon") || rel.contains("apple-touch-icon"),
                  let href = link.attribute(forName: "href")?.stringValue,
                  let url = webURL(URL(string: href, relativeTo: baseURL)?.absoluteURL) else { continue }
            let type = link.attribute(forName: "type")?.stringValue?.lowercased() ?? ""
            // ImageIO cannot reliably decode SVG icons on every supported macOS.
            let score = rel.contains("apple-touch-icon") ? 3 : (type.contains("png") || url.pathExtension.lowercased() == "png") ? 0 : (type.contains("svg") || url.pathExtension.lowercased() == "svg") ? 4 : 1
            if !candidates.contains(where: { $0.0 == url }) { candidates.append((url, score)) }
        }
        return candidates.enumerated().sorted { $0.element.1 == $1.element.1 ? $0.offset < $1.offset : $0.element.1 < $1.element.1 }.map { $0.element.0 }
    }
}
