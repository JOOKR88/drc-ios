import Foundation

enum AppConfig {
    static let host = "dreamerc.org"
    static let base = "https://dreamerc.org"
    /// الموقع يقرأ هذا من User-Agent (في الخادم) فيعرف إنه داخل تطبيق الآيفون:
    /// يخفي شريطه السفلي وسحب التحديث حقه لأن التطبيق يرسمها أصلياً.
    static let userAgentSuffix = "DRCiOS/1.0"

    /// يبقى داخل التطبيق: الموقع ونطاقاته الفرعية، وصفحات دخول ديسكورد فقط
    /// (الدخول يرجع للموقع بالكوكي، فلو انفتح في سفاري ضاعت الجلسة).
    /// أي شي ثاني ينفتح في نافذة سفاري داخل التطبيق.
    static func isInternal(_ url: URL) -> Bool {
        guard let h = url.host?.lowercased() else { return false }
        if h == host || h.hasSuffix("." + host) { return true }
        let discordHosts = ["discord.com", "discordapp.com"]
        if discordHosts.contains(where: { h == $0 || h.hasSuffix("." + $0) }) {
            let p = url.path.lowercased()
            return ["/oauth2", "/login", "/register", "/api/oauth2"].contains(where: { p.hasPrefix($0) })
        }
        return false
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case home, leaderboard, shop, souls, dashboard, profile

    var id: String { rawValue }

    var path: String {
        switch self {
        case .home: return "/"
        case .leaderboard: return "/leaderboard"
        case .shop: return "/shop"
        case .souls: return "/souls"
        case .dashboard: return "/dashboard"
        case .profile: return "/profile"
        }
    }

    /// نفس أسماء شريط الموقع على الجوال (`AppShellMobile`) عشان التجربة وحدة.
    var title: String {
        switch self {
        case .home: return "الرئيسية"
        case .leaderboard: return "المتصدرون"
        case .shop: return "المتجر"
        case .souls: return "Souls"
        case .dashboard: return "اللوحة"
        case .profile: return "حسابي"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .leaderboard: return "chart.bar.fill"
        case .shop: return "bag.fill"
        case .souls: return "book.closed.fill"
        case .dashboard: return "square.grid.2x2.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }

    var url: URL { URL(string: AppConfig.base + path)! }

    /// الشريط يعرض ٥ تبويبات بحد أقصى (السادس يصير «المزيد» ويخرّب الشكل)،
    /// فاللوحة لما تتفعّل تاخذ مكان المتجر — والمتجر يبقى من الرئيسية وحسابي.
    static func visible(dashboard: Bool) -> [AppTab] {
        dashboard
            ? [.home, .leaderboard, .dashboard, .souls, .profile]
            : [.home, .leaderboard, .shop, .souls, .profile]
    }

    /// شاشات SwiftUI أصلية؛ الباقي (المتجر واللوحة) صفحات الموقع داخل التطبيق.
    var isNative: Bool {
        switch self {
        case .home, .leaderboard, .souls, .profile: return true
        case .shop, .dashboard: return false
        }
    }
}

/// مفاتيح إعدادات التطبيق (UserDefaults) — كل ميزة إضافية تنطفي وتشتغل من «إعدادات التطبيق».
enum SettingKey {
    static let dashboardTab = "dashboardTab"
    static let quickActions = "quickActions"
    static let lockEnabled = "lockEnabled"
    static let lockScope = "lockScope"
    static let lockGrace = "lockGrace"
}

enum LockScope: String {
    case app, dashboard
}
