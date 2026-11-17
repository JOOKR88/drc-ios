import SwiftUI
import UIKit

struct RootView: View {
    @StateObject private var store = WebStore()
    @State private var selection: AppTab = RootView.initialTab()
    @State private var showSplash = true

    /// لقطات الشاشة الآلية على GitHub تشغّل التطبيق بـ`-tab shop` مثلاً لتصوير كل تبويب.
    static func initialTab() -> AppTab {
        if let raw = UserDefaults.standard.string(forKey: "tab"), let tab = AppTab(rawValue: raw) {
            return tab
        }
        return .home
    }

    var body: some View {
        ZStack {
            TabView(selection: tabSelection) {
                ForEach(AppTab.allCases) { tab in
                    WebTabView(controller: store.controller(for: tab))
                        .tabItem { Label(tab.title, systemImage: tab.symbol) }
                        .tag(tab)
                }
            }
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        // العربي أولاً: التبويبات تبدأ من اليمين مثل الموقع
        .environment(\.layoutDirection, .rightToLeft)
        .onReceive(store.controller(for: RootView.initialTab()).$firstLoadDone) { done in
            if done { hideSplash() }
        }
        .task {
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
                    store.controller(for: newValue).popToRootOrTop()
                } else {
                    UISelectionFeedbackGenerator().selectionChanged()
                    selection = newValue
                }
            }
        )
    }

    private func hideSplash() {
        guard showSplash else { return }
        withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
    }
}

struct WebTabView: View {
    @ObservedObject var controller: WebController

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
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { controller.loadIfNeeded() }
        .sheet(item: $controller.externalURL) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
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
