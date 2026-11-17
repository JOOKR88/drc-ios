import SwiftUI

/// قائمة لوحة التحكم الأصلية: بدل قائمة الموقع الصغيرة على الجوال، صفوف كبيرة بأيقونات ملوّنة
/// (أسلوب إعدادات iOS) ومجموعات وبحث. كل قسم يفتح صفحته من الموقع بشاشة مكبّرة بلا القائمة الجانبية.
/// الأقسام مطابقة لـ`app/dashboard/layout.tsx` (منظور الأونر) — قسم جديد هناك يُضاف هنا.
struct DashSection: Identifiable, Hashable {
    let path: String
    let title: String
    let symbol: String
    var id: String { path }
}

struct DashGroup: Identifiable {
    let title: String
    let color: Color
    let items: [DashSection]
    var id: String { title }
}

enum DashboardCatalog {
    static let groups: [DashGroup] = [
        DashGroup(title: "عام", color: Color(red: 0.80, green: 0.75, blue: 0.68), items: [
            DashSection(path: "/dashboard", title: "نظرة عامة", symbol: "house.fill"),
            DashSection(path: "/dashboard/office", title: "المكتب", symbol: "lightbulb.fill"),
            DashSection(path: "/dashboard/stats", title: "الإحصائيات", symbol: "chart.bar.xaxis"),
            DashSection(path: "/dashboard/audit", title: "سجل التدقيق", symbol: "list.clipboard.fill"),
        ]),
        DashGroup(title: "الاقتصاد", color: Color(red: 0.30, green: 0.72, blue: 0.47), items: [
            DashSection(path: "/dashboard/points", title: "النقاط", symbol: "diamond.fill"),
            DashSection(path: "/dashboard/shop", title: "المنتجات", symbol: "tag.fill"),
            DashSection(path: "/dashboard/global", title: "اللوحة العامة", symbol: "globe"),
        ]),
        DashGroup(title: "المجتمع", color: Color(red: 0.45, green: 0.52, blue: 0.95), items: [
            DashSection(path: "/dashboard/announcements", title: "الإعلانات", symbol: "megaphone.fill"),
            DashSection(path: "/dashboard/sponsors", title: "الرعاية", symbol: "star.fill"),
            DashSection(path: "/dashboard/broadcast", title: "البث الجماعي", symbol: "bell.badge.fill"),
            DashSection(path: "/dashboard/social", title: "سوشل", symbol: "photo.on.rectangle"),
            DashSection(path: "/dashboard/crew", title: "منشن ‎@DRC", symbol: "at"),
            DashSection(path: "/dashboard/clans", title: "الكلانات", symbol: "shield.lefthalf.filled"),
            DashSection(path: "/dashboard/games", title: "الألعاب", symbol: "trophy.fill"),
            DashSection(path: "/dashboard/wiki", title: "خانات ويكي Souls", symbol: "books.vertical.fill"),
            DashSection(path: "/dashboard/credit", title: "تبديل الكردت", symbol: "arrow.triangle.2.circlepath"),
            DashSection(path: "/dashboard/support", title: "ادعمني", symbol: "cup.and.saucer.fill"),
            DashSection(path: "/dashboard/downloader", title: "لوحة التحميل", symbol: "tray.and.arrow.down.fill"),
            DashSection(path: "/dashboard/overlay", title: "أوفرلي — التراخيص", symbol: "cpu"),
        ]),
        DashGroup(title: "الطاقم", color: Color(red: 0.95, green: 0.60, blue: 0.30), items: [
            DashSection(path: "/dashboard/admins", title: "المشرفون", symbol: "checkmark.shield.fill"),
            DashSection(path: "/dashboard/staff", title: "ملفات الطاقم", symbol: "person.2.fill"),
            DashSection(path: "/dashboard/shifts", title: "دوام الإداريين", symbol: "clock.fill"),
            DashSection(path: "/dashboard/voice", title: "التحكم الصوتي", symbol: "mic.fill"),
        ]),
        DashGroup(title: "الأعمال", color: Color(red: 0.25, green: 0.72, blue: 0.75), items: [
            DashSection(path: "/dashboard/ark", title: "متجر آرك", symbol: "shippingbox.fill"),
            DashSection(path: "/dashboard/stores", title: "متاجر الأعضاء", symbol: "storefront.fill"),
        ]),
        DashGroup(title: "النظام", color: Color(red: 0.60, green: 0.60, blue: 0.64), items: [
            DashSection(path: "/dashboard/settings", title: "الإعدادات", symbol: "gearshape.fill"),
            DashSection(path: "/dashboard/features", title: "الميزات", symbol: "square.grid.3x3.fill"),
            DashSection(path: "/dashboard/app", title: "التطبيق", symbol: "iphone"),
            DashSection(path: "/dashboard/ai", title: "الذكاء الاصطناعي", symbol: "sparkles"),
            DashSection(path: "/dashboard/bot", title: "إعدادات البوت", symbol: "server.rack"),
        ]),
    ]

    static func title(for path: String) -> String {
        for g in groups {
            if let s = g.items.first(where: { $0.path == path }) { return s.title }
        }
        return "لوحة التحكم"
    }
}

/// التنقّل داخل تبويب اللوحة — اختصارات الأيقونة والودجت تفتح قسماً مباشرة من هنا.
@MainActor
final class DashboardNavigator: ObservableObject {
    static let shared = DashboardNavigator()
    @Published var path: [Route] = []

    func open(_ webPath: String) {
        path = webPath == "/dashboard" || webPath.isEmpty
            ? []
            : [.web(path: webPath, title: DashboardCatalog.title(for: webPath))]
    }
}

/// تبويب اللوحة نفسه (له شريط تنقّله).
struct DashboardTab: View {
    @ObservedObject private var nav = DashboardNavigator.shared

    var body: some View {
        NavigationStack(path: $nav.path) {
            DashboardMenu()
                .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
                .onReceive(AppRouter.shared.$reselected) { r in
                    if r?.tab == .dashboard { nav.path = [] }
                }
        }
    }
}

/// محتوى القائمة — يُستعمل في التبويب، ويُدفع من الرئيسية وحسابي.
struct DashboardMenu: View {
    @ObservedObject private var account = AccountStore.shared
    @EnvironmentObject private var lock: LockManager
    @AppStorage(SettingKey.lockEnabled) private var lockEnabled = false
    @AppStorage(SettingKey.lockScope) private var lockScope = LockScope.dashboard.rawValue
    @State private var query = ""

    private var locked: Bool {
        lockEnabled && lockScope == LockScope.dashboard.rawValue && !lock.unlocked
    }

    private var groups: [DashGroup] {
        let q = normalizeArabic(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return DashboardCatalog.groups }
        return DashboardCatalog.groups.compactMap { g in
            let items = g.items.filter { normalizeArabic($0.title).contains(q) }
            return items.isEmpty ? nil : DashGroup(title: g.title, color: g.color, items: items)
        }
    }

    var body: some View {
        ZStack {
            List {
                if query.isEmpty {
                    Section {
                        DashHeader(stats: account.ownerStats)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                ForEach(groups) { g in
                    Section {
                        ForEach(g.items) { item in
                            NavigationLink(value: Route.web(path: item.path, title: item.title)) {
                                DashRow(item: item, color: g.color, badge: badge(for: item))
                            }
                            .listRowBackground(Theme.surface)
                        }
                    } header: {
                        Text(g.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .environment(\.defaultMinListRowHeight, 58)

            if locked {
                LockView(title: "لوحة التحكم مقفولة") {
                    Task { await lock.authenticate(reason: "افتح لوحة التحكم") }
                }
            }
        }
        .navigationTitle("لوحة التحكم")
        .searchable(text: $query, prompt: "ابحث عن قسم")
        .refreshable { await account.refresh() }
        .task(id: locked) {
            if locked { await lock.authenticate(reason: "افتح لوحة التحكم") }
        }
    }

    private func badge(for item: DashSection) -> Int? {
        if item.path == "/dashboard/ark", let n = account.ownerStats?.arkNew, n > 0 { return n }
        return nil
    }
}

private struct DashRow: View {
    let item: DashSection
    let color: Color
    let badge: Int?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(item.title)
                .font(.body.weight(.medium))
                .foregroundStyle(Theme.content)
            Spacer(minLength: 6)
            if let badge {
                Text("\(badge)")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.goldText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.gold, in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DashHeader: View {
    let stats: WidgetStats?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("الأونر")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                Text("OWNER")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Theme.goldText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.champagne, in: Capsule())
                Spacer()
                if let s = stats {
                    HStack(spacing: 5) {
                        Circle().fill(s.botOk ? Color.green : Color.red).frame(width: 7, height: 7)
                        Text(s.botOk ? "البوت شغّال" : "البوت واقف")
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            if let s = stats {
                HStack(spacing: 8) {
                    tile("أعضاء", s.members.map(Fmt.compact) ?? "—")
                    tile("نشطين ٧ أيام", Fmt.compact(s.active7d))
                    tile("آرك جديد", Fmt.compact(s.arkNew), accent: s.arkNew > 0)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    private func tile(_ title: String, _ value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(accent ? Theme.gold : Theme.content)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title).font(.caption).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.edge.opacity(0.7), lineWidth: 1))
    }
}
