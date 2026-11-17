import SwiftUI
import UIKit
import WebKit

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

/// متصفّح تبويب واحد. كل تبويب له نسخة تعيش طول عمر التطبيق،
/// فالرجوع لتبويب يرجّعك لنفس الصفحة ونفس مكان التمرير بلا تحميل.
@MainActor
final class WebController: NSObject, ObservableObject {
    let startURL: URL
    let rootPath: String
    let webView: WKWebView
    /// يُنادى بعد اكتمال كل صفحة (شاشة الدخول تعرف منه إن الدخول تمّ).
    var onFinish: ((URL) -> Void)?

    @Published var progress: Double = 0
    @Published var isLoading = false
    @Published var failed = false
    @Published var firstLoadDone = false
    @Published var externalURL: IdentifiableURL?
    /// مسار الصفحة الحالية — يتحدّث حتى مع تنقّل الموقع الداخلي (pushState)، وعليه يعتمد قفل اللوحة.
    @Published var path: String = ""
    @Published var title: String = ""

    private var observers: [NSKeyValueObservation] = []
    private let refresh = UIRefreshControl()

    convenience init(tab: AppTab) {
        self.init(startURL: startURL, rootPath: rootPath)
    }

    /// `hideAppChrome`: صفحة موقع داخل شاشة أصلية (فوقها شريط تنقّل iOS)، فنخفي رأس الموقع داخل التطبيق
    /// من جهة التطبيق فقط — الموقع نفسه ما يتغيّر.
    init(startURL: URL, rootPath: String, hideAppChrome: Bool = false) {
        self.startURL = startURL
        self.rootPath = rootPath

        let config = WKWebViewConfiguration()
        // نفس مخزن الكوكي لكل التبويبات: تسجّل دخول مرة وحدة وتنفع في الكل
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // «Safari» في التعريف عشان ديسكورد وغيره يعاملونه كسفاري عادي، و«DRCiOS» عشان موقعنا يعرفه
        config.applicationNameForUserAgent = "Version/18.0 Mobile/15E148 Safari/604.1 " + AppConfig.userAgentSuffix

        let ucc = WKUserContentController()
        // الموقع يستدعي navigator.vibrate عند اللمس (يشتغل على أندرويد فقط)؛
        // هنا نحوّله لاهتزاز iOS الأصلي بدل ما يضيع.
        let hapticShim = """
        (function () {
          try {
            Object.defineProperty(navigator, 'vibrate', {
              configurable: true,
              value: function (p) {
                try {
                  var ms = Array.isArray(p) ? (p[0] || 10) : (p || 10);
                  window.webkit.messageHandlers.drcHaptic.postMessage(ms);
                } catch (e) {}
                return true;
              }
            });
          } catch (e) {}
        })();
        """
        ucc.addUserScript(WKUserScript(source: hapticShim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if hideAppChrome {
            // محدّدات أعلى أولوية من أنماط الموقع فتغلبها مهما كان ترتيب تحميلها
            let css = "html body header.fixed.top-0.z-nav{display:none!important}html body main{padding-top:12px!important}"
            let js = "(function(){var s=document.createElement('style');s.textContent='" + css + "';(document.head||document.documentElement).appendChild(s);})();"
            ucc.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        config.userContentController = ucc

        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        ucc.add(WeakScriptHandler(self), name: "drcHaptic")

        webView.navigationDelegate = self
        webView.uiDelegate = self
        // داخل شاشة مدفوعة سحبة الرجوع لـiOS (ترجع للشاشة السابقة) لا لتاريخ الصفحة
        webView.allowsBackForwardNavigationGestures = !hideAppChrome
        webView.allowsLinkPreview = false
        // بدون هذي يطلع وميض أبيض قبل ما ترسم الصفحة الداكنة
        webView.isOpaque = false
        webView.backgroundColor = Theme.bgUI
        webView.scrollView.backgroundColor = Theme.bgUI
        // الموقع يحسب حواف الشاشة بنفسه (env(safe-area-inset-*))، فما نضيف إزاحة ثانية فوقها
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.keyboardDismissMode = .interactive
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }

        refresh.tintColor = Theme.goldUI
        refresh.addTarget(self, action: #selector(pulledToRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        observers.append(webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            let value = wv.estimatedProgress
            Task { @MainActor in self?.progress = value }
        })
        observers.append(webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
            let value = wv.url?.path ?? ""
            Task { @MainActor in self?.path = value }
        })
        observers.append(webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
            let value = wv.title ?? ""
            Task { @MainActor in self?.title = value }
        })
        observers.append(webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
            let value = wv.isLoading
            Task { @MainActor in self?.isLoading = value }
        })
    }

    /// التبويب يحمّل صفحته أول مرة يظهر فيها فقط — ما نحمّل الخمس صفحات مع بعض عند التشغيل.
    func loadIfNeeded() {
        guard webView.url == nil, !webView.isLoading else { return }
        webView.load(URLRequest(url: startURL))
    }

    /// يفتح مسار في الموقع داخل هذا التبويب (اختصارات الأيقونة).
    func open(path: String) {
        guard let url = URL(string: AppConfig.base + path) else { return }
        failed = false
        webView.load(URLRequest(url: url))
    }

    func retry() {
        failed = false
        if webView.url != nil {
            webView.reload()
        } else {
            webView.load(URLRequest(url: startURL))
        }
    }

    /// الضغط على التبويب المفتوح (سلوك iOS المعتاد): يرجع لأول صفحة في التبويب،
    /// ولو كنت فيها أصلاً يطلع لأعلى الصفحة.
    func popToRootOrTop() {
        let current = normalize(webView.url?.path)
        if current == normalize(rootPath) || webView.url == nil {
            webView.scrollView.setContentOffset(.zero, animated: true)
            return
        }
        if let first = webView.backForwardList.backList.first, normalize(first.url.path) == normalize(rootPath) {
            webView.go(to: first)
        } else {
            webView.load(URLRequest(url: startURL))
        }
    }

    @objc private func pulledToRefresh() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        retry()
    }

    private func normalize(_ path: String?) -> String {
        guard var p = path, !p.isEmpty else { return "/" }
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    private func handle(_ error: Error) {
        refresh.endRefreshing()
        let ns = error as NSError
        // الإلغاء (نقرة ثانية قبل ما تخلص الأولى، أو رابط حوّلناه لسفاري) مو خطأ
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return }
        failed = true
        firstLoadDone = true
    }
}

extension WebController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow)
            return
        }
        if ["about", "blob", "data"].contains(scheme) {
            decisionHandler(.allow)
            return
        }
        if scheme == "drc-app" {
            // أيقونة «إعدادات التطبيق» في رأس الموقع
            AppRouter.shared.handle(appURL: url)
            decisionHandler(.cancel)
            return
        }
        if scheme != "http" && scheme != "https" {
            // mailto: و tel: و discord:// تفتح في تطبيقاتها
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if isMainFrame && !AppConfig.isInternal(url) {
            externalURL = IdentifiableURL(url: url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refresh.endRefreshing()
        failed = false
        firstLoadDone = true
        if let url = webView.url { onFinish?(url) }
        Task { await WidgetBridge.refreshTokenIfNeeded() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handle(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // iOS يقفل محتوى الصفحة لما تضيق الذاكرة؛ بدل شاشة بيضاء نعيد التحميل
        webView.reload()
    }
}

extension WebController: WKUIDelegate {
    /// روابط «تفتح في نافذة جديدة»: الداخلية تفتح في نفس التبويب، والخارجية في سفاري داخل التطبيق.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            if AppConfig.isInternal(url) {
                webView.load(navigationAction.request)
            } else if url.scheme?.hasPrefix("http") == true {
                externalURL = IdentifiableURL(url: url)
            }
        }
        return nil
    }
}

extension WebController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "drcHaptic" else { return }
        let ms = (message.body as? NSNumber)?.doubleValue ?? 10
        UIImpactFeedbackGenerator(style: ms >= 20 ? .medium : .light).impactOccurred()
    }
}

/// WKUserContentController يمسك المعالج بقوة؛ هذا الوسيط يمنع حلقة احتفاظ تخلّي المتصفح ما ينفك من الذاكرة.
@MainActor
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// كل متصفحات التبويبات في مكان واحد، تنشأ عند أول طلب وتعيش طول التشغيل.
@MainActor
final class WebStore: ObservableObject {
    private var controllers: [AppTab: WebController] = [:]
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .drcSessionChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reloadAll() }
        }
    }

    func reloadAll() {
        for c in controllers.values where c.webView.url != nil {
            c.webView.reload()
        }
    }

    func controller(for tab: AppTab) -> WebController {
        if let existing = controllers[tab] { return existing }
        let created = WebController(tab: tab)
        controllers[tab] = created
        return created
    }
}
