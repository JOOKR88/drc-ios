import BackgroundTasks
import SwiftUI
import UIKit
import UserNotifications

/// يوصل طلبات «افتح كذا» من برّا الواجهة (اختصارات الأيقونة، وروابط drc-app:// من الموقع) إلى RootView.
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    static let settingsRoute = "settings"

    /// مسار في الموقع (مثل /dashboard/ark) أو `settings` لشاشة إعدادات التطبيق.
    @Published var pending: String?

    /// الضغط على التبويب المفتوح نفسه (سلوك iOS): الشاشة ترجع لأولها وتطلع لفوق.
    @Published var reselected: (tab: AppTab, at: Date)?

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

/// SwiftUI ما يوصّل اختصارات الأيقونة ولا الإشعارات ولا مهام الخلفية بنفسه؛ نحتاج مندوب التطبيق والمشهد.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // فحص التنبيهات في الخلفية — لازم يتسجّل قبل ما يخلص الإقلاع
        BGTaskScheduler.shared.register(forTaskWithIdentifier: NotifPoller.taskID, using: nil) { task in
            Task { @MainActor in
                NotifPoller.schedule()
                let ok = await NotifPoller.check(background: true)
                task.setTaskCompleted(success: ok)
            }
            task.expirationHandler = { task.setTaskCompleted(success: false) }
        }
        return true
    }

    /// الإشعار يظهر حتى والتطبيق مفتوح (بانر فوق).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// الضغط على الإشعار: يفتح الرسالة داخل التطبيق مباشرة (بجلسة التطبيق، بلا «سجّل») ويعلّمها مقروءة.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let href = info["href"] as? String ?? "/notifications"
        let id = info["id"] as? String
        await MainActor.run {
            AppRouter.shared.pending = href
        }
        if let id {
            await NotificationsStore.shared.markRead(id)
        }
    }

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
