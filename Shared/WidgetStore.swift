import Foundation

/// مخزن مشترك بين التطبيق والودجت (App Group): التطبيق يحفظ رمز الودجت، والودجت يقرأه ويحفظ آخر أرقام.
///
/// مع التوقيع المجاني (SideStore) اسم المجموعة يتغيّر حسب حساب Apple، وSideStore يكتب الاسم
/// الفعلي في `ALTAppGroups` داخل Info.plist التطبيق — فنقرأه من هناك، والودجت يقرأه من التطبيق الأم.
enum WidgetStore {
    static let baseGroup = "group.org.dreamerc.app"

    static var groupID: String {
        let key = "ALTAppGroups"
        if let group = (Bundle.main.object(forInfoDictionaryKey: key) as? [String])?.first {
            return group
        }
        let url = Bundle.main.bundleURL
        if url.pathExtension == "appex" {
            let appURL = url.deletingLastPathComponent().deletingLastPathComponent()
            if let group = (Bundle(url: appURL)?.object(forInfoDictionaryKey: key) as? [String])?.first {
                return group
            }
        }
        return baseGroup
    }

    static var defaults: UserDefaults? { UserDefaults(suiteName: groupID) }

    static var token: String? {
        get { defaults?.string(forKey: "widgetToken") }
        set { defaults?.set(newValue, forKey: "widgetToken") }
    }

    static var tokenFetchedAt: Date? {
        get { defaults?.object(forKey: "widgetTokenAt") as? Date }
        set { defaults?.set(newValue, forKey: "widgetTokenAt") }
    }

    static var lastStats: Data? {
        get { defaults?.data(forKey: "widgetStats") }
        set { defaults?.set(newValue, forKey: "widgetStats") }
    }
}

struct WidgetStats: Codable {
    var members: Int?
    var active7d: Int
    var growthPct: Int?
    var visits7d: Int
    var arkNew: Int
    var arkActive: Int
    var botOk: Bool
    var at: String

    static let sample = WidgetStats(
        members: 4500, active7d: 620, growthPct: 8, visits7d: 3100,
        arkNew: 1, arkActive: 2, botOk: true, at: ""
    )
}
