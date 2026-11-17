import WidgetKit

/// رمز الودجت: يُطلب من الموقع بجلسة الأونر (كوكي المتصفح) ويُحفظ في المخزن المشترك مع الودجت.
/// للأونر فقط: غيره يرجع له 403 وما يصير شي. الرمز صالح ٣٠ يوم ونجدّده كل يوم.
@MainActor
enum WidgetBridge {
    private static var lastAttempt: Date?

    static func refreshTokenIfNeeded() async {
        if WidgetStore.token != nil, let at = WidgetStore.tokenFetchedAt, Date().timeIntervalSince(at) < 86_400 {
            return
        }
        // مو مسجّل أو مو الأونر: ما نعيد الطلب مع كل صفحة، مرة كل ١٠ دقائق تكفي
        if let last = lastAttempt, Date().timeIntervalSince(last) < 600 { return }
        lastAttempt = Date()
        guard let data = try? await API.get("/api/app/widget-token"),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = obj["token"] as? String else { return }
        WidgetStore.token = token
        WidgetStore.tokenFetchedAt = Date()
        WidgetCenter.shared.reloadAllTimelines()
    }

    static var isLinked: Bool { WidgetStore.token != nil }

    static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        WidgetStore.token = nil
        WidgetStore.tokenFetchedAt = nil
        lastAttempt = nil
        WidgetCenter.shared.reloadAllTimelines()
    }
}
