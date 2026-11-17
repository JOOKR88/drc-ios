import SwiftUI

struct ProfileView: View {
    @ObservedObject private var account = AccountStore.shared
    @State private var showLogin = false
    @State private var confirmLogout = false

    var body: some View {
        NavigationStack {
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
                        row("التنبيهات", "bell", .web(path: "/notifications", title: "التنبيهات"))
                        row("المتجر", "bag", .web(path: "/shop", title: "المتجر"))
                        row("طلبات آرك", "shippingbox", .web(path: "/ark/orders", title: "طلبات آرك"))
                    }
                    if account.isOwner {
                        Section("الإدارة") {
                            row("لوحة التحكم", "square.grid.2x2", .dashboardMenu)
                            row("طلبات آرك (اللوحة)", "tray.full", .web(path: "/dashboard/ark", title: "طلبات آرك"))
                            row("الإحصائيات", "chart.xyaxis.line", .web(path: "/dashboard/stats", title: "الإحصائيات"))
                        }
                    }
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

    private func row(_ title: String, _ symbol: String, _ route: Route) -> some View {
        NavigationLink(value: route) {
            Label(title, systemImage: symbol)
                .foregroundStyle(Theme.content)
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
                    chip(Fmt.n(s.points) + " نقطة")
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
