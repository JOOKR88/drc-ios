import SwiftUI

/// وجهات التنقّل داخل الشاشات الأصلية.
enum Route: Hashable {
    case web(path: String, title: String)
    case article(slug: String)
}

struct RouteDestination: View {
    let route: Route

    var body: some View {
        switch route {
        case .web(let path, let title):
            WebScreen(path: path, title: title)
        case .article(let slug):
            ArticleView(slug: slug)
        }
    }
}

/// صفحة من الموقع داخل شاشة أصلية: شريط تنقّل iOS فوق، وزر الرجوع وسحبته يرجعانك للشاشة السابقة.
struct WebScreen: View {
    let title: String
    @StateObject private var controller: WebController
    @EnvironmentObject private var lock: LockManager
    @AppStorage(SettingKey.lockEnabled) private var lockEnabled = false
    @AppStorage(SettingKey.lockScope) private var lockScope = LockScope.dashboard.rawValue

    init(path: String, title: String) {
        self.title = title
        let url = URL(string: AppConfig.base + path) ?? URL(string: AppConfig.base)!
        _controller = StateObject(wrappedValue: WebController(startURL: url, rootPath: path, hideAppChrome: true))
    }

    private var locked: Bool {
        lockEnabled && lockScope == LockScope.dashboard.rawValue && !lock.unlocked
            && controller.path.hasPrefix("/dashboard")
    }

    var body: some View {
        ZStack(alignment: .top) {
            WebViewContainer(webView: controller.webView)
            if controller.isLoading && controller.progress < 1 {
                ProgressLine(progress: controller.progress)
            }
            if controller.failed {
                OfflineView { controller.retry() }
            }
            if locked {
                LockView(title: "لوحة التحكم مقفولة") {
                    Task { await lock.authenticate(reason: "افتح لوحة التحكم") }
                }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { controller.loadIfNeeded() }
        .task(id: locked) {
            if locked { await lock.authenticate(reason: "افتح لوحة التحكم") }
        }
        .sheet(item: $controller.externalURL) { item in
            SafariView(url: item.url).ignoresSafeArea()
        }
    }
}

/// الدخول بديسكورد: صفحة دخول الموقع نفسها في ورقة، وأول ما ترجع لصفحة من الموقع خارج /login نقفلها.
struct LoginSheet: View {
    var done: () -> Void
    @StateObject private var controller = WebController(
        startURL: URL(string: AppConfig.base + "/login?next=%2Fprofile")!,
        rootPath: "/login",
        hideAppChrome: true
    )
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                WebViewContainer(webView: controller.webView)
                if controller.isLoading && controller.progress < 1 {
                    ProgressLine(progress: controller.progress)
                }
                if controller.failed {
                    OfflineView { controller.retry() }
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("تسجيل الدخول")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear {
            controller.onFinish = { url in
                guard url.host == AppConfig.host else { return }
                let p = url.path
                if !p.hasPrefix("/login") && !p.hasPrefix("/api/auth") {
                    Haptic.tap()
                    done()
                    dismiss()
                }
            }
            controller.loadIfNeeded()
        }
    }
}

/// بطاقة الترحيب لمن لم يسجّل دخول.
struct WelcomeCard: View {
    var login: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 120)
                .padding(.top, 6)
            Text("أهلاً في DRC")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.content)
            Text("سجّل دخولك بديسكورد عشان تشوف نقاطك ومستواك وترتيبك.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
            Button {
                Haptic.tap()
                login()
            } label: {
                Label("دخول عبر Discord", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.headline)
                    .foregroundStyle(Theme.goldText)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 13)
                    .background(Theme.champagne, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .card(radius: 26, padding: 24)
    }
}
