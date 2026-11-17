import WebKit
import WidgetKit

/// يجيب رمز الودجت من الموقع بجلسة الأونر (من داخل صفحة مفتوحة، فالكوكي موجود) ويسلّمه للودجت.
/// للأونر فقط: غيره يرجع له 403 وما يصير شي. الرمز صالح ٣٠ يوم ونجدّده كل يوم.
@MainActor
enum WidgetBridge {
    private static var inFlight = false
    private static var lastAttempt: Date?

    static func refreshTokenIfNeeded(using webView: WKWebView) {
        guard !inFlight, webView.url?.host == AppConfig.host else { return }
        if WidgetStore.token != nil, let at = WidgetStore.tokenFetchedAt, Date().timeIntervalSince(at) < 86_400 {
            return
        }
        // مو مسجّل أو مو الأونر: ما نعيد الطلب مع كل صفحة، مرة كل ١٠ دقائق تكفي
        if let last = lastAttempt, Date().timeIntervalSince(last) < 600 { return }
        lastAttempt = Date()
        inFlight = true
        let js = """
        const r = await fetch('/api/app/widget-token', { credentials: 'same-origin', cache: 'no-store' });
        if (!r.ok) { return ''; }
        return await r.text();
        """
        webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
            Task { @MainActor in
                inFlight = false
                guard case .success(let value) = result,
                      let text = value as? String,
                      let data = text.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let token = obj["token"] as? String else { return }
                WidgetStore.token = token
                WidgetStore.tokenFetchedAt = Date()
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    static var isLinked: Bool { WidgetStore.token != nil }

    static func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
