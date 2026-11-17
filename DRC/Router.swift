import SwiftUI
import UIKit

/// يوصل طلبات «افتح كذا» من برّا الواجهة (اختصارات الأيقونة، وروابط drc-app:// من الموقع) إلى RootView.
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    static let settingsRoute = "settings"

    /// مسار في الموقع (مثل /dashboard/ark) أو `settings` لشاشة إعدادات التطبيق.
    @Published var pending: String?

    func handle(_ item: UIApplicationShortcutItem) {
        if let path = item.userInfo?["path"] as? String {
            pending = path
        }
    }

    /// روابط `drc-app://settings` من رأس الموقع داخل التطبيق.
    func handle(appURL url: URL) {
        switch url.host {
        case "settings":
            pending = AppRouter.settingsRoute
        case "open":
            // drc-app://open/dashboard — الضغط على الودجت
            pending = url.path.isEmpty ? "/" : url.path
        default:
            break
        }
    }

    /// اختصارات الضغطة المطوّلة على الأيقونة — تنضاف أو تنشال حسب الإعداد.
    static func applyShortcuts(enabled: Bool) {
        guard enabled else {
            UIApplication.shared.shortcutItems = []
            return
        }
        func item(_ type: String, _ title: String, _ symbol: String, _ path: String) -> UIApplicationShortcutItem {
            UIApplicationShortcutItem(
                type: "org.dreamerc.app." + type,
                localizedTitle: title,
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: symbol),
                userInfo: ["path": path as NSString]
            )
        }
        UIApplication.shared.shortcutItems = [
            item("dashboard", "لوحة التحكم", "square.grid.2x2.fill", "/dashboard"),
            item("ark", "طلبات آرك", "shippingbox.fill", "/dashboard/ark"),
            item("notifications", "التنبيهات", "bell.fill", "/notifications"),
            item("settings", "إعدادات التطبيق", "slider.horizontal.3", settingsRoute),
        ]
    }
}

/// SwiftUI ما يوصّل اختصارات الأيقونة بنفسه؛ نحتاج مندوب التطبيق والمشهد.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // تشغيل من الصفر عن طريق اختصار
        if let item = options.shortcutItem {
            AppRouter.shared.handle(item)
        }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    // التطبيق شغّال بالخلفية واختار المستخدم اختصاراً
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        AppRouter.shared.handle(shortcutItem)
        completionHandler(true)
    }
}
