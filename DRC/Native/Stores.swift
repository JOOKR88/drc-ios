import SwiftUI
import WebKit

/// الحساب: الجلسة + ملخّص النقاط + (للأونر) أرقام المنصّة. كلها تبدأ من آخر نسخة محفوظة.
@MainActor
final class AccountStore: ObservableObject {
    static let shared = AccountStore()

    @Published private(set) var user: SessionInfo.User?
    @Published private(set) var summary: MeSummary?
    @Published private(set) var ownerStats: WidgetStats?
    /// تنبيهات الموقع غير المقروءة — عدّاد على تبويب «حسابي».
    @Published private(set) var unread = 0
    /// nil = لسه ما نعرف (أول تشغيل بلا نت)
    @Published private(set) var loggedIn: Bool?

    private init() {
        if let s = DiskCache.decode(SessionInfo.self, "session") {
            user = s.user
            loggedIn = s.user != nil
        }
        summary = DiskCache.decode(MeSummary.self, "me")
        ownerStats = DiskCache.decode(WidgetStats.self, "owner-stats")
    }

    var isOwner: Bool { WidgetStore.token != nil && loggedIn == true }

    func refresh() async {
        do {
            let sd = try await API.get("/api/auth/session")
            let s = try? JSONDecoder().decode(SessionInfo.self, from: sd)
            if let s, s.user != nil {
                user = s.user
                loggedIn = true
                DiskCache.write("session", sd)
            } else {
                clearLocal()
                return
            }
            let md = try await API.get("/api/me/summary")
            if let m = try? JSONDecoder().decode(MeSummary.self, from: md) {
                withAnimation(.snappy) { summary = m }
                DiskCache.write("me", md)
            }
            await refreshUnread()
            await WidgetBridge.refreshTokenIfNeeded()
            await loadOwnerStats()
        } catch APIError.unauthorized {
            clearLocal()
        } catch {
            // بلا نت: نبقي آخر نسخة
        }
    }

    func refreshUnread() async {
        guard loggedIn == true,
              let d = try? await API.get("/api/notifications?summary=1"),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        unread = (obj["unread"] as? Int) ?? 0
    }

    private func loadOwnerStats() async {
        guard let token = WidgetStore.token,
              let d = try? await API.request("/api/app/widget", bearer: token),
              let s = try? JSONDecoder().decode(WidgetStats.self, from: d) else { return }
        withAnimation(.snappy) { ownerStats = s }
        DiskCache.write("owner-stats", d)
        WidgetStore.lastStats = d
    }

    private func clearLocal() {
        user = nil
        summary = nil
        ownerStats = nil
        unread = 0
        loggedIn = false
        DiskCache.remove("session")
        DiskCache.remove("me")
        DiskCache.remove("owner-stats")
    }

    /// خروج من التطبيق: نمسح كوكي المتصفح (الجلسة) ورمز الودجت.
    func logout() async {
        await WKWebsiteDataStore.default().removeData(
            ofTypes: [WKWebsiteDataTypeCookies],
            modifiedSince: .distantPast
        )
        WidgetBridge.clear()
        clearLocal()
        NotificationCenter.default.post(name: .drcSessionChanged, object: nil)
    }
}

@MainActor
final class LeaderboardStore: ObservableObject {
    static let shared = LeaderboardStore()
    static let boards = ["xp", "rich", "rep", "week"]

    @Published private(set) var data: [String: LeaderboardResponse] = [:]
    private var loadedAt: [String: Date] = [:]

    private init() {
        for b in Self.boards {
            if let r = DiskCache.decode(LeaderboardResponse.self, "lb-" + b) { data[b] = r }
        }
    }

    func load(_ board: String, force: Bool = false) async {
        if !force, let at = loadedAt[board], Date().timeIntervalSince(at) < 30 { return }
        guard let d = try? await API.get("/api/app/leaderboard?board=" + board),
              let r = try? JSONDecoder().decode(LeaderboardResponse.self, from: d) else { return }
        withAnimation(.snappy) { data[board] = r }
        loadedAt[board] = Date()
        DiskCache.write("lb-" + board, d)
    }

    func search(_ q: String) async -> [LbRow] {
        let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        guard let d = try? await API.get("/api/leaderboard/search?q=" + encoded),
              let r = try? JSONDecoder().decode(SearchResponse.self, from: d) else { return [] }
        return r.rows
    }
}

@MainActor
final class SoulsStore: ObservableObject {
    static let shared = SoulsStore()

    @Published private(set) var index: SoulsIndex?
    private var loadedAt: Date?

    private init() {
        index = DiskCache.decode(SoulsIndex.self, "souls-index")
    }

    func loadIndex(force: Bool = false) async {
        if !force, let at = loadedAt, Date().timeIntervalSince(at) < 120 { return }
        guard let d = try? await API.get("/api/app/souls"),
              let r = try? JSONDecoder().decode(SoulsIndex.self, from: d) else { return }
        withAnimation(.snappy) { index = r }
        loadedAt = Date()
        DiskCache.write("souls-index", d)
    }

    func cachedArticle(_ slug: String) -> Article? {
        DiskCache.decode(Article.self, "souls-" + slug)
    }

    /// المقال يُحفظ بعد أول قراءة — فيفتح بعدها بدون نت.
    func article(_ slug: String) async -> Article? {
        let path = "/api/app/souls/" + (slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug)
        guard let d = try? await API.get(path),
              let a = try? JSONDecoder().decode(Article.self, from: d) else { return nil }
        DiskCache.write("souls-" + slug, d)
        return a
    }

    /// نفس عدّاد المشاهدات اللي يستعمله الموقع.
    func countView(_ id: String) async {
        let body = try? JSONSerialization.data(withJSONObject: ["action": "view"])
        _ = try? await API.request("/api/souls/" + id, method: "POST", body: body)
    }

    func game(_ key: String) -> SoulsGame? { index?.games.first { $0.key == key } }
}

extension Color {
    /// ألوان الألعاب تجي من الموقع بصيغة #RRGGBB.
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt64(s, radix: 16) ?? 0x888888
        self.init(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }
}

/// تطبيع عربي بسيط للبحث: بلا تشكيل، والألف والتاء المربوطة والياء بأشكالها واحد.
func normalizeArabic(_ s: String) -> String {
    var t = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ar"))
    for (a, b) in [("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ة", "ه"), ("ى", "ي"), ("ـ", "")] {
        t = t.replacingOccurrences(of: a, with: b)
    }
    return t
}
