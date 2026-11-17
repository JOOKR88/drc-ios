import SwiftUI

/// الرئيسية الأصلية: تفتح لحظياً بآخر بيانات محفوظة، ثم تتحدّث.
struct HomeView: View {
    var selectTab: (AppTab) -> Void
    @ObservedObject private var account = AccountStore.shared
    @State private var showLogin = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HomeHeader(user: account.user)

                    if account.loggedIn == false {
                        WelcomeCard { showLogin = true }
                    } else if let s = account.summary {
                        PointsCard(s: s)
                        if account.isOwner, let o = account.ownerStats {
                            OwnerStatsCard(stats: o)
                        }
                        QuickGrid(isOwner: account.isOwner, selectTab: selectTab)
                        if !s.weekly.isEmpty { WeeklyCard(rows: s.weekly) }
                        if !s.recent.isEmpty { ActivityCard(items: s.recent) }
                        if !s.souls.isEmpty { SoulsStrip(items: s.souls, selectTab: selectTab) }
                    } else {
                        Skeleton(height: 200, radius: 28)
                        Skeleton(height: 96)
                        Skeleton(height: 220)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .refreshable { await account.refresh() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
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
}

private struct HomeHeader: View {
    let user: SessionInfo.User?

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "صباح الخير" : "مساء الخير"
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                Text(user?.name ?? "DRC")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Theme.content)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            Button {
                Haptic.tap()
                AppRouter.shared.pending = AppRouter.settingsRoute
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.content)
                    .frame(width: 44, height: 44)
                    .floatingGlass(radius: 22)
            }
            .buttonStyle(PressableStyle())
            if let image = user?.image {
                Avatar(url: image, size: 44, ring: Theme.gold.opacity(0.6))
            }
        }
        .padding(.top, 8)
    }
}

/// بطاقة الرصيد بالشامبين المعدني — هوية DRC.
private struct PointsCard: View {
    let s: MeSummary
    @State private var shown = false

    private var progress: Double {
        s.needed > 0 ? min(1, Double(s.intoLevel) / Double(s.needed)) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("رصيدك")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.goldText.opacity(0.65))
                    Text(Fmt.n(shown ? s.points : 0))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.goldText)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("نقطة")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.goldText.opacity(0.6))
                }
                Spacer()
                LevelRing(level: s.level, progress: shown ? progress : 0)
            }
            HStack(spacing: 8) {
                Pill(title: "الترتيب", value: s.rank.map { "#" + Fmt.n($0) } ?? "—")
                Pill(title: "اليوم", value: "+" + Fmt.n(s.today))
                Pill(title: "الأسبوع", value: "+" + Fmt.n(s.myWeek))
            }
        }
        .padding(20)
        .background(Theme.champagne, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.85)) { shown = true }
        }
    }

    private struct Pill: View {
        let title: String
        let value: String

        var body: some View {
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.goldText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.goldText.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

private struct LevelRing: View {
    let level: Int
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(Theme.goldText.opacity(0.15), lineWidth: 7)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.goldText, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("المستوى")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.goldText.opacity(0.6))
                Text("\(level)")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.goldText)
            }
        }
        .frame(width: 78, height: 78)
    }
}

/// أرقام المنصّة للأونر (نفس أرقام الودجت).
private struct OwnerStatsCard: View {
    let stats: WidgetStats

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("أرقام المنصّة")
                    .font(.headline)
                    .foregroundStyle(Theme.content)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(stats.botOk ? Color.green : Color.red).frame(width: 7, height: 7)
                    Text(stats.botOk ? "البوت شغّال" : "البوت واقف")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            HStack(spacing: 10) {
                cell("أعضاء", stats.members.map(Fmt.n) ?? "—")
                cell("نشطين ٧ أيام", Fmt.n(stats.active7d))
            }
            HStack(spacing: 10) {
                cell("زوار ٧ أيام", Fmt.n(stats.visits7d))
                cell("آرك جديد", Fmt.n(stats.arkNew), accent: stats.arkNew > 0)
            }
        }
        .card()
    }

    private func cell(_ title: String, _ value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(accent ? Theme.gold : Theme.content)
            Text(title).font(.caption).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.bg.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct QuickGrid: View {
    let isOwner: Bool
    var selectTab: (AppTab) -> Void

    private struct Item: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let route: Route?
        let tab: AppTab?
    }

    private var items: [Item] {
        var list: [Item] = [
            Item(id: "shop", title: "المتجر", symbol: "bag.fill", route: .web(path: "/shop", title: "المتجر"), tab: nil),
            Item(id: "souls", title: "Souls", symbol: "book.closed.fill", route: nil, tab: .souls),
            Item(id: "ark", title: "آرك", symbol: "shippingbox.fill", route: .web(path: "/ark", title: "متجر آرك"), tab: nil),
            Item(id: "bell", title: "التنبيهات", symbol: "bell.fill", route: .web(path: "/notifications", title: "التنبيهات"), tab: nil),
        ]
        if isOwner {
            list.append(Item(id: "dash", title: "اللوحة", symbol: "square.grid.2x2.fill", route: .dashboardMenu, tab: nil))
            list.append(Item(id: "arkorders", title: "طلبات آرك", symbol: "tray.full.fill", route: .web(path: "/dashboard/ark", title: "طلبات آرك"), tab: nil))
            list.append(Item(id: "stats", title: "الإحصائيات", symbol: "chart.xyaxis.line", route: .web(path: "/dashboard/stats", title: "الإحصائيات"), tab: nil))
            list.append(Item(id: "sugg", title: "الاقتراحات", symbol: "lightbulb.fill", route: .web(path: "/suggestions", title: "الاقتراحات"), tab: nil))
        }
        return list
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(items) { item in
                if let route = item.route {
                    NavigationLink(value: route) { tile(item) }
                        .buttonStyle(PressableStyle())
                        .simultaneousGesture(TapGesture().onEnded { Haptic.tap() })
                } else if let tab = item.tab {
                    Button {
                        Haptic.tap()
                        selectTab(tab)
                    } label: { tile(item) }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private func tile(_ item: Item) -> some View {
        VStack(spacing: 8) {
            Image(systemName: item.symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.gold)
                .frame(width: 52, height: 52)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.edge, lineWidth: 1))
            Text(item.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.content)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WeeklyCard: View {
    let rows: [MeSummary.WeeklyRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "الأنشط هذا الأسبوع", subtitle: "مجموع النقاط منذ ٧ أيام")
            ForEach(Array(rows.prefix(5).enumerated()), id: \.offset) { i, r in
                HStack(spacing: 12) {
                    Text("\(i + 1)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(i == 0 ? Theme.gold : Theme.muted)
                        .frame(width: 22)
                    Avatar(url: r.avatar, size: 36)
                    Text(r.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.content)
                        .lineLimit(1)
                    Spacer()
                    Text("+" + Fmt.n(r.points))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.gold)
                }
            }
        }
        .card()
    }
}

private struct ActivityCard: View {
    let items: [MeSummary.Txn]

    private func meta(_ source: String) -> (String, String) {
        switch source {
        case "MESSAGE": return ("رسائل", "bubble.left.and.bubble.right.fill")
        case "VOICE": return ("الصوت", "mic.fill")
        case "REACTION": return ("تفاعل", "face.smiling.inverse")
        case "DAILY": return ("المكافأة اليومية", "calendar")
        case "SHOP", "PURCHASE": return ("المتجر", "bag.fill")
        case "TRANSFER": return ("تحويل", "arrow.left.arrow.right")
        case "ADMIN", "AWARD", "GRANT": return ("مكافأة", "gift.fill")
        default: return ("نقاط", "sparkles")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "آخر حركاتك")
            ForEach(Array(items.enumerated()), id: \.offset) { _, t in
                let m = meta(t.source)
                HStack(spacing: 12) {
                    Image(systemName: m.1)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.gold)
                        .frame(width: 34, height: 34)
                        .background(Theme.bg.opacity(0.7), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text((t.note?.isEmpty == false ? t.note : nil) ?? m.0)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.content)
                            .lineLimit(1)
                        Text(Fmt.ago(t.at)).font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text((t.amount >= 0 ? "+" : "") + Fmt.n(t.amount))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(t.amount >= 0 ? Color.green : Color.red)
                }
            }
        }
        .card()
    }
}

private struct SoulsStrip: View {
    let items: [MeSummary.SoulCard]
    var selectTab: (AppTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(title: "جديد Souls")
                Button("الكل") {
                    Haptic.tap()
                    selectTab(.souls)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.gold)
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(items, id: \.href) { a in
                        NavigationLink(value: Route.article(slug: a.slug)) {
                            ZStack(alignment: .bottomLeading) {
                                RemoteImage(url: a.image)
                                    .frame(width: 230, height: 150)
                                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                                Text(a.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .padding(12)
                            }
                            .frame(width: 230, height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}
