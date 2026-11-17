import SwiftUI
import UIKit

struct RootView: View {
    @StateObject private var store = WebStore()
    @StateObject private var lock = LockManager()
    @ObservedObject private var router = AppRouter.shared
    @ObservedObject private var account = AccountStore.shared
    @State private var selection: AppTab = RootView.initialTab()
    @State private var showSplash = true
    @State private var showSettings = false
    @State private var webSheet: SheetRoute?
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(SettingKey.dashboardTab) private var dashboardTab = true
    @AppStorage(SettingKey.quickActions) private var quickActions = true
    @AppStorage(SettingKey.lockEnabled) private var lockEnabled = false
    @AppStorage(SettingKey.lockScope) private var lockScope = LockScope.dashboard.rawValue
    @AppStorage(SettingKey.lockGrace) private var lockGrace = 60

    /// لقطات الشاشة الآلية على GitHub تشغّل التطبيق بـ`-tab shop` مثلاً لتصوير كل تبويب.
    static func initialTab() -> AppTab {
        if let raw = UserDefaults.standard.string(forKey: "tab"), let tab = AppTab(rawValue: raw) {
            return tab
        }
        return .home
    }

    private var tabs: [AppTab] { AppTab.visible(dashboard: dashboardTab) }
    private var appLocked: Bool { lockEnabled && lockScope == LockScope.app.rawValue && !lock.unlocked }
    private var dashboardLockOn: Bool { lockEnabled && lockScope == LockScope.dashboard.rawValue }

    var body: some View {
        ZStack {
            TabView(selection: tabSelection) {
                ForEach(tabs) { tab in
                    tabContent(tab)
                        .tabItem { Label(tab.title, systemImage: tab.symbol) }
                        .badge(tab == .profile ? account.unread : 0)
                        .tag(tab)
                }
            }

            if appLocked {
                LockView(title: "التطبيق مقفول") { unlock() }
                    .transition(.opacity)
                    .zIndex(1)
            }

            // يخفي المحتوى في شاشة تبديل التطبيقات لما يكون القفل مفعّل
            if lockEnabled && scenePhase != .active {
                PrivacyCover().zIndex(2)
            }

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        // العربي أولاً: التبويبات تبدأ من اليمين مثل الموقع
        .environment(\.layoutDirection, .rightToLeft)
        .environmentObject(lock)
        .sheet(item: $webSheet) { item in
            NavigationStack {
                WebScreen(path: item.path, title: item.title)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("إغلاق") { webSheet = nil }
                        }
                    }
            }
            .environmentObject(lock)
            .environment(\.layoutDirection, .rightToLeft)
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(lock)
                .environment(\.layoutDirection, .rightToLeft)
                .preferredColorScheme(.dark)
        }
        .onReceive(store.controller(for: RootView.initialTab()).$firstLoadDone) { done in
            if done && !RootView.initialTab().isNative { hideSplash() }
        }
        .onOpenURL { url in
            router.handle(appURL: url)
        }
        .onReceive(router.$pending) { route in
            guard let route else { return }
            router.pending = nil
            open(route)
        }
        .onChange(of: dashboardTab) { _ in
            if !tabs.contains(selection) { selection = .home }
        }
        .onChange(of: quickActions) { on in
            AppRouter.applyShortcuts(enabled: on)
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .background: lock.didEnterBackground()
            case .active:
                lock.didBecomeActive(grace: lockGrace)
                Task { await account.refreshUnread() }
            default: break
            }
        }
        .task(id: appLocked) {
            // التطبيق مقفول كامل: نطلب الوجه على طول بدل ما ينتظر ضغطة
            if appLocked && scenePhase == .active { unlock() }
        }
        .task {
            AppRouter.applyShortcuts(enabled: quickActions)
            if RootView.initialTab().isNative {
                // الشاشات الأصلية تفتح من الكاش فوراً — الشعار لحظة بس
                try? await Task.sleep(nanoseconds: 450_000_000)
                hideSplash()
            }
            // لقطات GitHub: `-openSettings YES` يفتح شاشة الإعدادات للتصوير
            if UserDefaults.standard.bool(forKey: "openSettings") { showSettings = true }
            // لو الشبكة بطيئة ما نعلّق المستخدم على الشعار — بعد ٦ ثوانٍ تظهر الصفحة وشريط التحميل
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            hideSplash()
        }
    }

    /// الضغط على التبويب المفتوح نفسه = رجوع لأول صفحته (سلوك iOS المعتاد).
    private var tabSelection: Binding<AppTab> {
        Binding(
            get: { selection },
            set: { newValue in
                if newValue == selection {
                    if newValue.isNative {
                        router.reselected = (newValue, Date())
                    } else {
                        store.controller(for: newValue).popToRootOrTop()
                    }
                } else {
                    UISelectionFeedbackGenerator().selectionChanged()
                    selection = newValue
                }
            }
        )
    }

    /// اختصار أيقونة أو رابط drc-app:// — يفتح المسار في التبويب المناسب.
    private func open(_ route: String) {
        if route == AppRouter.settingsRoute {
            showSettings = true
            return
        }
        if let exact = tabs.first(where: { $0.path == route }) {
            selection = exact
            if !exact.isNative { store.controller(for: exact).open(path: route) }
        } else if dashboardTab && route.hasPrefix("/dashboard") {
            selection = .dashboard
            DashboardNavigator.shared.open(route)
        } else {
            // مسار بلا تبويب: صفحة الموقع في ورقة فوق التطبيق
            webSheet = SheetRoute(path: route, title: route.hasPrefix("/dashboard") ? "لوحة التحكم" : "DRC")
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView(selectTab: { t in
                Haptic.select()
                selection = tabs.contains(t) ? t : .home
            })
        case .leaderboard:
            LeaderboardView()
        case .souls:
            SoulsView()
        case .profile:
            ProfileView()
        case .dashboard:
            DashboardTab()
        case .shop:
            WebTabView(controller: store.controller(for: tab), dashboardLock: dashboardLockOn, lock: lock)
        }
    }

    private func unlock() {
        Task { @MainActor in
            await lock.authenticate(reason: "افتح DRC")
        }
    }

    private func hideSplash() {
        guard showSplash else { return }
        withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
    }
}

struct WebTabView: View {
    @ObservedObject var controller: WebController
    var dashboardLock: Bool
    @ObservedObject var lock: LockManager
    @Environment(\.scenePhase) private var scenePhase

    /// قفل «لوحة التحكم فقط»: يغطي أي تبويب صفحته الحالية من اللوحة.
    private var locked: Bool {
        dashboardLock && !lock.unlocked && controller.path.hasPrefix("/dashboard")
    }

    var body: some View {
        ZStack(alignment: .top) {
            WebViewContainer(webView: controller.webView)
                .ignoresSafeArea(edges: .top)

            if controller.isLoading && controller.progress < 1 {
                ProgressLine(progress: controller.progress)
            }

            if controller.failed {
                OfflineView { controller.retry() }
            }

            if locked {
                LockView(title: "لوحة التحكم مقفولة") { unlock() }
                    .transition(.opacity)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear {
            controller.applyZoom()
            controller.loadIfNeeded()
        }
        .task(id: locked) {
            if locked && scenePhase == .active { unlock() }
        }
        .sheet(item: $controller.externalURL) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
    }

    private func unlock() {
        Task { @MainActor in
            await lock.authenticate(reason: "افتح لوحة التحكم")
        }
    }
}

/// المتصفح يعيش في المتحكّم لا في الواجهة: لو أعادت SwiftUI بناء الحاوية
/// ننقل نفس المتصفح لها بدل ما ننشئ واحد جديد ونخسر الصفحة.
struct WebViewContainer: UIViewRepresentable {
    let webView: UIView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = Theme.bgUI
        attach(to: container)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if webView.superview !== uiView {
            attach(to: uiView)
        }
    }

    private func attach(to container: UIView) {
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}

struct SheetRoute: Identifiable {
    let id = UUID()
    let path: String
    let title: String
}
