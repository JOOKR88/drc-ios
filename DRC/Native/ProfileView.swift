import SwiftUI

struct ProfileView: View {
    @ObservedObject private var account = AccountStore.shared
    @State private var showLogin = false
    @State private var confirmLogout = false
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if account.loggedIn == false {
                    Section {
                        WelcomeCard { showLogin = true }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ProfileHeader(user: account.user, summary: account.summary)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    Section("حسابي") {
                        row("صفحتي في الموقع", "person.text.rectangle", .web(path: "/profile", title: "صفحتي"))
                        row("سيرفراتي", "server.rack", .web(path: "/servers", title: "سيرفراتي"))
                        row("التنبيهات", "bell", .web(path: "/notifications", title: "التنبيهات"), badge: account.unread)
                        row("المتجر", "bag", .web(path: "/shop", title: "المتجر"))
                        row("طلبات آرك", "shippingbox", .web(path: "/ark/orders", title: "طلبات آرك"))
                    }
                    Section("المجتمع") {
                        row("الاقتراحات", "lightbulb", .web(path: "/suggestions", title: "الاقتراحات"))
                        row("أضف البوت لسيرفرك", "plus.app", .web(path: "/bot", title: "أضف البوت"))
                        row("أعلن معنا", "megaphone", .web(path: "/advertise", title: "أعلن معنا"))
                    }
                    if account.isOwner {
                        Section("الإدارة") {
                            row("لوحة التحكم", "square.grid.2x2", .dashboardMenu)
                            row("طلبات آرك (اللوحة)", "tray.full", .web(path: "/dashboard/ark", title: "طلبات آرك"))
                            row("الإحصائيات", "chart.xyaxis.line", .stats)
                        }
                    }
                }
                Section("عن DRC") {
                    row("السياسات", "doc.text", .web(path: "/policies", title: "السياسات"))
                    row("تواصل معنا", "envelope", .web(path: "/contact", title: "تواصل معنا"))
                }
                Section("التطبيق") {
                    Button {
                        Haptic.tap()
                        AppRouter.shared.pending = AppRouter.settingsRoute
                    } label: {
                        Label("إعدادات التطبيق", systemImage: "slider.horizontal.3")
                            .foregroundStyle(Theme.content)
                    }
                    if account.loggedIn == true {
                        Button(role: .destructive) {
                            confirmLogout = true
                        } label: {
                            Label("تسجيل خروج", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("حسابي")
            .refreshable { await account.refresh() }
            .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
            .onReceive(AppRouter.shared.$reselected) { r in
                if r?.tab == .profile { path = [] }
            }
            .confirmationDialog("تسجيل الخروج من التطبيق؟", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("تسجيل خروج", role: .destructive) {
                    Task { await account.logout() }
                }
                Button("إلغاء", role: .cancel) {}
            }
        }
        .sheet(isPresented: $showLogin) {
            LoginSheet {
                Task {
                    await account.refresh()
                    NotificationCenter.default.post(name: .drcSessionChanged, object: nil)
                }
            }
        }
        .task { await account.refresh() }
    }

    private func row(_ title: String, _ symbol: String, _ route: Route, badge: Int = 0) -> some View {
        NavigationLink(value: route) {
            HStack {
                Label(title, systemImage: symbol)
                    .foregroundStyle(Theme.content)
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.goldText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Theme.gold, in: Capsule())
                }
            }
        }
        .listRowBackground(Theme.surface)
    }
}

private struct ProfileHeader: View {
    let user: SessionInfo.User?
    let summary: MeSummary?

    var body: some View {
        VStack(spacing: 12) {
            Avatar(url: user?.image, size: 92, ring: Theme.gold)
                .shadow(color: Theme.gold.opacity(0.35), radius: 16)
            Text(user?.name ?? "—")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.content)
            if let s = summary {
                HStack(spacing: 8) {
                    chip("المستوى \(s.level)")
                    if let r = s.rank { chip("#" + Fmt.n(r)) }
                    chip(Fmt.compact(s.points) + " نقطة")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.content)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.surface2, in: Capsule())
            .overlay(Capsule().stroke(Theme.edge, lineWidth: 1))
    }
}
