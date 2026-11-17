import SwiftUI
import WebKit

/// قارئ Souls: المقال من الكاش أولاً (يفتح بدون نت بعد أول قراءة)، في قالب قراءة خاص بالتطبيق
/// (خط النظام، تباعد مريح، صورة غلاف) — بلا جافاسكربت الموقع، فيفتح أسرع بكثير.
struct ArticleView: View {
    let slug: String
    @ObservedObject private var store = SoulsStore.shared
    @State private var article: Article?
    @State private var failed = false
    @State private var zoom: IdentifiableURL?
    @State private var external: IdentifiableURL?
    @State private var pushed: Route?
    @State private var showPushed = false
    @State private var counted = false
    @AppStorage(SettingKey.readerSize) private var readerSize = 17

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if let a = article {
                ReaderView(article: a, fontSize: readerSize, onImage: { zoom = IdentifiableURL(url: $0) }, onLink: handle)
                    .ignoresSafeArea(edges: [.top, .bottom])
                    .transition(.opacity)
            } else if failed {
                OfflineView { Task { await load() } }
            } else {
                ProgressView().tint(Theme.gold)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if let a = article, let url = URL(string: AppConfig.base + "/souls/" + a.slug) {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("حجم الخط", selection: $readerSize) {
                            Text("صغير").tag(15)
                            Text("عادي").tag(17)
                            Text("كبير").tag(19)
                            Text("أكبر").tag(22)
                        }
                    } label: {
                        Image(systemName: "textformat.size")
                    }
                }
            }
        }
        .task { await load() }
        .fullScreenCover(item: $zoom) { item in ImageViewer(url: item.url) }
        .sheet(item: $external) { item in SafariView(url: item.url).ignoresSafeArea() }
        .navigationDestination(isPresented: $showPushed) {
            if let pushed { RouteDestination(route: pushed) }
        }
    }

    private func load() async {
        failed = false
        if article == nil, let cached = store.cachedArticle(slug) {
            article = cached
        }
        if let fresh = await store.article(slug) {
            withAnimation(.easeOut(duration: 0.2)) { article = fresh }
            if !counted {
                counted = true
                await store.countView(fresh.id)
            }
        } else if article == nil {
            failed = true
        }
    }

    /// روابط داخل المقال: مقال Souls ثاني ينفتح بالقارئ، صفحة من موقعنا بشاشة الموقع، والباقي سفاري.
    private func handle(_ url: URL) {
        if url.host == AppConfig.host || url.host == "www." + AppConfig.host {
            let p = url.path
            if p.hasPrefix("/souls/"), p.split(separator: "/").count == 2 {
                pushed = .article(slug: String(p.split(separator: "/")[1]))
            } else {
                pushed = .web(path: p + (url.query.map { "?" + $0 } ?? ""), title: "DRC")
            }
            showPushed = true
        } else if url.scheme?.hasPrefix("http") == true {
            external = IdentifiableURL(url: url)
        }
    }
}

struct ReaderView: UIViewRepresentable {
    let article: Article
    var fontSize: Int = 17
    var onImage: (URL) -> Void
    var onLink: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.userContentController.add(context.coordinator, name: "drcImage")
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = Theme.bgUI
        wv.scrollView.backgroundColor = Theme.bgUI
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.navigationDelegate = context.coordinator
        wv.allowsLinkPreview = false
        context.coordinator.loadedID = article.id + article.updatedAt
        context.coordinator.fontSize = fontSize
        wv.loadHTMLString(ReaderTemplate.html(article, fontSize: fontSize), baseURL: URL(string: AppConfig.base))
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        context.coordinator.parent = self
        let key = article.id + article.updatedAt
        if context.coordinator.loadedID != key {
            context.coordinator.loadedID = key
            context.coordinator.fontSize = fontSize
            wv.loadHTMLString(ReaderTemplate.html(article, fontSize: fontSize), baseURL: URL(string: AppConfig.base))
        } else if context.coordinator.fontSize != fontSize {
            // تغيير حجم الخط بدون إعادة تحميل (يحافظ على مكان القراءة)
            context.coordinator.fontSize = fontSize
            wv.evaluateJavaScript("document.body.style.fontSize='\(fontSize)px'")
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: ReaderView
        var loadedID = ""
        var fontSize = 17

        init(_ parent: ReaderView) { self.parent = parent }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                parent.onLink(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let s = message.body as? String, let url = Fmt.absolute(s) {
                Haptic.tap()
                parent.onImage(url)
            }
        }
    }
}

enum ReaderTemplate {
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func html(_ a: Article, fontSize: Int = 17) -> String {
        let hero = Fmt.absolute(a.image).map { "<div class=\"hero\" style=\"background-image:url('\(esc($0.absoluteString))')\"></div>" } ?? ""
        let author: String = {
            guard let name = a.author.name, !name.isEmpty else { return "" }
            let img = a.author.avatar.map { "<img src=\"\(esc($0))\" alt=\"\">" } ?? ""
            return "<span class=\"author\">\(img)\(esc(name))</span><span>·</span>"
        }()
        let tags = a.tags.map { "<span>#\(esc($0))</span>" }.joined()
        let views = Fmt.compact(a.views)
        return """
        <!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
        <style>
        :root{color-scheme:dark}
        html,body{margin:0;background:#0B0A09;color:#E6E0D7;font:\(fontSize)px/1.9 -apple-system,"SF Arabic",system-ui,sans-serif;-webkit-text-size-adjust:100%;-webkit-tap-highlight-color:transparent}
        .hero{height:58vh;min-height:320px;background:#141210 center/cover no-repeat;position:relative}
        .hero::after{content:"";position:absolute;inset:0;background:linear-gradient(180deg,rgba(11,10,9,.55) 0%,rgba(11,10,9,0) 28%,rgba(11,10,9,.55) 68%,#0B0A09 100%)}
        .head{position:relative;z-index:2;padding:0 20px}
        .has-hero .head{margin-top:-150px}
        .no-hero .head{padding-top:calc(env(safe-area-inset-top) + 20px)}
        .badge{display:inline-block;font-size:12px;font-weight:700;padding:4px 11px;border-radius:999px;background:\(a.accent)E0;color:#fff}
        h1{font-size:30px;line-height:1.3;margin:12px 0 12px;color:#F7F3EC;font-weight:800;letter-spacing:-.2px}
        .meta{display:flex;flex-wrap:wrap;gap:8px;align-items:center;color:#91897D;font-size:13px;margin-bottom:6px}
        .author{display:inline-flex;align-items:center;gap:6px;color:#CFC8BE;font-weight:600}
        .author img{width:24px;height:24px;border-radius:50%}
        article{padding:10px 20px 30px;overflow-wrap:anywhere}
        article p{margin:0 0 14px}
        article img{max-width:100%;height:auto;border-radius:16px;display:block;margin:18px auto;cursor:zoom-in}
        article a{color:#CCBFAE;text-decoration:none;border-bottom:1px solid rgba(204,191,174,.35)}
        article h1,article h2,article h3{color:#F7F3EC;line-height:1.4;margin:30px 0 10px}
        article h2{font-size:23px} article h3{font-size:19px}
        blockquote{margin:18px 0;padding:12px 16px;border-inline-start:3px solid #CCBFAE;background:#141210;border-radius:12px;color:#D3CCC2}
        ul,ol{padding-inline-start:22px} li{margin:4px 0}
        hr{border:0;border-top:1px solid #312D28;margin:26px 0}
        code{background:#1C1A17;border-radius:6px;padding:1px 6px;font-size:.9em}
        pre{background:#141210;border-radius:12px;padding:12px;overflow-x:auto}
        table{border-collapse:collapse;display:block;overflow-x:auto;margin:16px 0} td,th{border:1px solid #312D28;padding:6px 10px}
        iframe,video{max-width:100%;border-radius:14px}
        .tags{display:flex;flex-wrap:wrap;gap:8px;padding:0 20px calc(env(safe-area-inset-bottom) + 40px)}
        .tags span{font-size:13px;color:#B0A89D;background:#141210;border:1px solid #312D28;border-radius:999px;padding:4px 12px}
        </style></head>
        <body class="\(a.image == nil ? "no-hero" : "has-hero")">
        \(hero)
        <div class="head">
          <span class="badge">\(esc(a.gameName))</span>
          <h1>\(esc(a.title))</h1>
          <div class="meta">\(author)<span>\(a.minutes) دقائق قراءة</span><span>·</span><span>\(views) مشاهدة</span></div>
        </div>
        <article>\(a.content)</article>
        <div class="tags">\(tags)</div>
        <script>
        document.querySelectorAll('article img').forEach(function(img){
          var a = img.closest('a'); if (a) { a.addEventListener('click', function(e){ e.preventDefault(); }); }
          img.addEventListener('click', function(){ try { webkit.messageHandlers.drcImage.postMessage(img.currentSrc || img.src); } catch(e){} });
        });
        </script>
        </body></html>
        """
    }
}

/// عارض الصورة: تكبير بإصبعين، ونقرتين للتكبير السريع، وسحب لتحت للإغلاق.
struct ImageViewer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var drag: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(1 - min(abs(drag.height) / 400, 0.6)).ignoresSafeArea()
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFit()
                } else {
                    ProgressView().tint(.white)
                }
            }
            .scaleEffect(scale)
            .offset(drag)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gesture(
                MagnificationGesture()
                    .onChanged { v in scale = max(1, lastScale * v) }
                    .onEnded { _ in lastScale = scale }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { v in if scale == 1 { drag = v.translation } }
                    .onEnded { v in
                        if scale == 1 && abs(v.translation.height) > 120 {
                            dismiss()
                        } else {
                            withAnimation(.spring()) { drag = .zero }
                        }
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    scale = scale > 1 ? 1 : 2.5
                    lastScale = scale
                }
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(20)
        }
        .statusBarHidden()
    }
}
