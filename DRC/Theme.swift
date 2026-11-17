import SwiftUI
import UIKit

/// ألوان هوية الموقع في الوضع الداكن (`globals.css`) — التطبيق داكن دائماً مثل الموقع افتراضياً.
enum Theme {
    static let bgUI = UIColor(red: 11 / 255, green: 10 / 255, blue: 9 / 255, alpha: 1)        // --c-bg
    static let surfaceUI = UIColor(red: 20 / 255, green: 18 / 255, blue: 16 / 255, alpha: 1)  // --c-surface
    static let edgeUI = UIColor(red: 49 / 255, green: 45 / 255, blue: 40 / 255, alpha: 1)     // --c-edge
    static let goldUI = UIColor(red: 204 / 255, green: 191 / 255, blue: 174 / 255, alpha: 1)  // --c-gold-strong
    static let mutedUI = UIColor(red: 145 / 255, green: 137 / 255, blue: 125 / 255, alpha: 1) // --c-faint
    static let contentUI = UIColor(red: 240 / 255, green: 236 / 255, blue: 229 / 255, alpha: 1)

    static let bg = Color(uiColor: bgUI)
    static let surface = Color(uiColor: surfaceUI)
    static let gold = Color(uiColor: goldUI)
    static let muted = Color(uiColor: mutedUI)
    static let content = Color(uiColor: contentUI)
    static let goldText = Color(red: 28 / 255, green: 24 / 255, blue: 19 / 255)

    /// شريط التبويبات: سطح داكن معتم + الشامبين للنشط، مثل شريط الموقع.
    static func applyUIKitAppearance() {
        let a = UITabBarAppearance()
        a.configureWithOpaqueBackground()
        a.backgroundColor = surfaceUI
        a.shadowColor = edgeUI
        for item in [a.stackedLayoutAppearance, a.inlineLayoutAppearance, a.compactInlineLayoutAppearance] {
            item.normal.iconColor = mutedUI
            item.normal.titleTextAttributes = [.foregroundColor: mutedUI]
            item.selected.iconColor = goldUI
            item.selected.titleTextAttributes = [.foregroundColor: goldUI]
        }
        UITabBar.appearance().standardAppearance = a
        UITabBar.appearance().scrollEdgeAppearance = a
    }
}
