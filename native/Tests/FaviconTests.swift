import AppKit
import Foundation

@main struct FaviconTests {
    @MainActor static func main() async throws {
        let base = URL(string: CommandLine.arguments[1])!
        let html = Data("<html><head><base href='/assets/'><link rel='icon' type='image/svg+xml' href='mark.svg'><link rel='shortcut icon' type='image/png' href='mark.png'><link rel='icon' href='javascript:bad'><link rel='apple-touch-icon' href='touch.png'></head></html>".utf8)
        let candidates = FaviconLoader.candidates(in: html, base: base.appendingPathComponent("nested/page"))
        assert(candidates.map(\.lastPathComponent) == ["mark.png", "touch.png", "mark.svg"])
        assert(candidates[0].path == "/assets/mark.png")
        let relative = FaviconLoader.candidates(in: Data("<html><head><link rel='icon' href='assets/favicon.png'></head></html>".utf8), base: base.appendingPathComponent("nested/page"))
        assert(relative.first?.path == "/nested/assets/favicon.png")
        let loader = FaviconLoader()
        async let first = loader.image(for: base.appendingPathComponent("redirect").absoluteString)
        async let duplicate = loader.image(for: base.appendingPathComponent("redirect").absoluteString)
        let (one, two) = await (first, duplicate)
        assert(one != nil && two != nil && one === two, "Concurrent requests must share the decoded image")
        assert(one!.size.width <= 64 && one!.size.height <= 64, "Downsample large icons")
        let cached = await loader.image(for: base.appendingPathComponent("another-page").absoluteString)
        assert(cached === one, "Cache across the same origin")
        let unsafe = await loader.image(for: "file:///tmp/private")
        assert(unsafe == nil)
        let missing = FaviconLoader()
        let failure = await missing.image(for: base.appendingPathComponent("missing").absoluteString)
        let cachedFailure = await missing.image(for: base.appendingPathComponent("missing").absoluteString)
        assert(failure == nil && cachedFailure == nil)
        if CommandLine.arguments.contains("--live") {
            let live = await FaviconLoader().image(for: "https://derivativebrowser.com/")
            assert(live != nil, "Derivative's live declared favicon must decode")
            print("PASS: derivativebrowser.com favicon decoded successfully.")
        }
        print("PASS: page-declared PNG favicon, redirects, relative/base URLs, invalid schemes, downsampling, shared cache, and negative cache.")
    }
}
