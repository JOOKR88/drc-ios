import SwiftUI

@main
struct DRCApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Theme.applyUIKitAppearance()
        // صور الأفاتارات والمقالات تنحفظ على الجوال: التنقّل بين الشاشات بدون إعادة تنزيل
        URLCache.shared = URLCache(memoryCapacity: 60_000_000, diskCapacity: 400_000_000)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
    }
}
