import Foundation
import WebKit

enum APIError: Error {
    case unauthorized
    case http(Int)
}

/// طلبات الشاشات الأصلية. الجلسة تعيش في متصفح التطبيق (WKWebView)، فنقرأ كوكيها لكل طلب —
/// تسجيل الدخول مرة وحدة يكفي الشاشات الأصلية وصفحات الموقع معاً.
@MainActor
enum API {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpShouldSetCookies = false
        c.httpCookieStorage = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }()

    static let userAgent = "DRC-iOS/1.0 (iPhone) " + AppConfig.userAgentSuffix

    static func cookieHeader() async -> String? {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        let mine = cookies.filter { $0.domain.hasSuffix(AppConfig.host) }
        guard !mine.isEmpty else { return nil }
        return HTTPCookie.requestHeaderFields(with: mine)["Cookie"]
    }

    static func request(_ path: String, method: String = "GET", body: Data? = nil, bearer: String? = nil) async throws -> Data {
        guard let url = URL(string: AppConfig.base + path) else { throw APIError.http(0) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let bearer {
            req.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
        } else if let cookie = await cookieHeader() {
            req.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        let (data, response) = try await session.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(code) else { throw APIError.http(code) }
        return data
    }

    static func get(_ path: String) async throws -> Data {
        try await request(path)
    }
}

/// آخر رد لكل شاشة على القرص: الشاشة تفتح لحظياً بآخر بيانات (حتى بدون نت) ثم تتحدّث.
enum DiskCache {
    static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("drc-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private static func file(_ key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "-" ? String($0) : "_" }.joined()
        return dir.appendingPathComponent(safe + ".json")
    }

    static func read(_ key: String) -> Data? { try? Data(contentsOf: file(key)) }
    static func write(_ key: String, _ data: Data) { try? data.write(to: file(key), options: .atomic) }
    static func remove(_ key: String) { try? FileManager.default.removeItem(at: file(key)) }

    static func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = read(key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

enum Fmt {
    static let number: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        return f
    }()

    static func n(_ v: Int) -> String { number.string(from: NSNumber(value: v)) ?? "\(v)" }

    static func date(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }

    static func ago(_ iso: String) -> String {
        guard let d = date(iso) else { return "" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ar")
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }

    static func absolute(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: path.hasPrefix("/") ? AppConfig.base + path : path)
    }
}

extension Notification.Name {
    /// دخول أو خروج: صفحات الموقع المفتوحة تعيد التحميل والشاشات الأصلية تحدّث بياناتها.
    static let drcSessionChanged = Notification.Name("drcSessionChanged")
}
