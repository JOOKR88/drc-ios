import Charts
import SwiftUI

// MARK: - البيانات (نفس شكل `Analytics` في lib/analytics.ts)

struct StatTrend: Codable {
    let value: Double
    let prev: Double
    let pct: Int?
    let noPrev: Bool?
}

struct StatDay: Codable, Identifiable {
    let label: String
    let value: Double
    var id: String { label }
}

struct StatEcon: Codable, Identifiable {
    let label: String
    let minted: Double
    let sunk: Double
    var id: String { label }
}

struct StatSource: Codable {
    let src: String
    let value: Double
}

struct StatPage: Codable {
    let path: String
    let views: Int
    let visitors: Int
}

struct StatAnalytics: Codable {
    struct Peaks: Codable {
        let dow: Int?
        let quietDow: Int?
        let hour: Int?
    }
    struct AllTime: Codable {
        let minted: Double
        let spent: Double
    }
    let period: Int
    let since: String?
    let messages: StatTrend
    let voiceHours: StatTrend
    let earned: StatTrend
    let spent: StatTrend
    let purchases: StatTrend
    let newMembers: StatTrend
    let visits: StatTrend
    let uniqueVisitors: StatTrend
    let activeMembers: StatTrend
    let byDow: [Double]
    let byHour: [Double]
    let peaks: Peaks
    let byDay: [StatDay]
    let visitsByDay: [StatDay]
    let newByDay: [StatDay]
    let econByDay: [StatEcon]
    let sources: [StatSource]
    let topPages: [StatPage]
    let allTime: AllTime
}

struct StatsResponse: Codable {
    let period: Int
    let memberCount: Int?
    let analytics: StatAnalytics
}

@MainActor
final class StatsStore: ObservableObject {
    static let shared = StatsStore()
    @Published private(set) var data: [Int: StatsResponse] = [:]
    @Published private(set) var denied = false
    /// الرد وصل لكن ما انقرأ (تغيّر شكل البيانات في الموقع) — نعرض رسالة وزر الصفحة الكاملة بدل هيكل تحميل للأبد
    @Published private(set) var unreadable = false
    private var loadedAt: [Int: Date] = [:]

    private init() {
        for p in [7, 30, 90] {
            if let r = DiskCache.decode(StatsResponse.self, "stats-\(p)") { data[p] = r }
        }
    }

    func load(_ period: Int, force: Bool = false) async {
        if !force, let at = loadedAt[period], Date().timeIntervalSince(at) < 60 { return }
        do {
            let d = try await API.get("/api/app/stats?d=\(period)")
            guard let r = try? JSONDecoder().decode(StatsResponse.self, from: d) else {
                unreadable = true
                return
            }
            withAnimation(.snappy) { data[period] = r }
            denied = false
            unreadable = false
            loadedAt[period] = Date()
            DiskCache.write("stats-\(period)", d)
        } catch APIError.unauthorized {
            denied = true
        } catch APIError.http(403) {
            denied = true
        } catch {
            // بلا نت: آخر نسخة
        }
    }
}

// MARK: - الشاشة

/// الإحصائيات بشاشة أصلية: بطاقات بنسبة التغيّر، ورسوم iOS تلمسها وتشوف قيمة كل يوم.
struct StatsView: View {
    @ObservedObject private var store = StatsStore.shared
    @EnvironmentObject private var lock: LockManager
    @AppStorage(SettingKey.lockEnabled) private var lockEnabled = false
    @AppStorage(SettingKey.lockScope) private var lockScope = LockScope.dashboard.rawValue
    @State private var period = 30

    private var locked: Bool {
        lockEnabled && lockScope == LockScope.dashboard.rawValue && !lock.unlocked
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("الفترة", selection: $period) {
                        Text("٧ أيام").tag(7)
                        Text("٣٠ يوم").tag(30)
                        Text("٩٠ يوم").tag(90)
                    }
                    .pickerStyle(.segmented)

                    if let r = store.data[period] {
                        StatsContent(r: r)
                            .id(period)
                            .transition(.opacity)
                    } else if store.denied {
                        Text("الإحصائيات للأونر ومن عنده صلاحيتها. سجّل دخول بحسابك.")
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 30)
                    } else if store.unreadable {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("تعذّر عرض الإحصائيات هنا — افتح الصفحة الكاملة.")
                                .foregroundStyle(Theme.muted)
                            NavigationLink(value: Route.web(path: "/dashboard/stats?d=\(period)", title: "الإحصائيات")) {
                                Label("الإحصائيات في الموقع", systemImage: "safari")
                                    .font(.headline)
                                    .foregroundStyle(Theme.goldText)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 11)
                                    .background(Theme.champagne, in: Capsule())
                            }
                        }
                        .padding(.top, 20)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(0..<6, id: \.self) { _ in Skeleton(height: 96, radius: 18) }
                        }
                        Skeleton(height: 240)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())

            if locked {
                LockView(title: "لوحة التحكم مقفولة") {
                    Task { await lock.authenticate(reason: "افتح لوحة التحكم") }
                }
            }
        }
        .navigationTitle("الإحصائيات")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: Route.web(path: "/dashboard/stats?d=\(period)", title: "الإحصائيات الكاملة")) {
                    Image(systemName: "safari")
                }
            }
        }
        .onChange(of: period) { _ in Haptic.select() }
        .task(id: period) { await store.load(period) }
        .refreshable { await store.load(period, force: true) }
        .task(id: locked) {
            if locked { await lock.authenticate(reason: "افتح لوحة التحكم") }
        }
    }
}

private struct StatsContent: View {
    let r: StatsResponse
    private var a: StatAnalytics { r.analytics }

    private static let days = ["الأحد", "الاثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"]
    private static let sourceNames: [String: String] = [
        "MESSAGE": "رسائل", "VOICE": "صوت", "REACTION": "تفاعل", "DAILY": "يومية", "PURCHASE": "شراء",
        "ADMIN": "إداري", "TRANSFER": "تحويل", "BOOST": "بوست", "SHOP": "شراء", "GIVE": "تحويل",
        "CREDIT": "تبديل كردت", "EVENT": "فعالية", "LEVEL": "ترقية مستوى",
    ]

    static func hourName(_ h: Int) -> String {
        if h == 0 { return "١٢ ص" }
        if h < 12 { return "\(h) ص" }
        if h == 12 { return "١٢ م" }
        return "\(h - 12) م"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let m = r.memberCount {
                HStack(spacing: 6) {
                    Image(systemName: "person.3.fill").foregroundStyle(Theme.gold)
                    Text("أعضاء السيرفر")
                        .foregroundStyle(Theme.muted)
                    Text(Fmt.compact(m))
                        .font(.headline)
                        .foregroundStyle(Theme.content)
                }
                .font(.subheadline)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                Kpi(title: "النشطون", symbol: "person.2.fill", t: a.activeMembers)
                Kpi(title: "الأعضاء الجدد", symbol: "person.badge.plus", t: a.newMembers)
                Kpi(title: "الرسائل", symbol: "bubble.left.fill", t: a.messages)
                Kpi(title: "ساعات الصوت", symbol: "mic.fill", t: a.voiceHours)
                Kpi(title: "النقاط المكتسبة", symbol: "sparkles", t: a.earned)
                Kpi(title: "المصروف بالمتجر", symbol: "bag.fill", t: a.spent)
                Kpi(title: "زيارات الموقع", symbol: "eye.fill", t: a.visits)
                Kpi(title: "الزوار", symbol: "person.crop.circle", t: a.uniqueVisitors)
            }

            LineCard(title: "النشطون يومياً", unit: "عضو", points: a.byDay)
            BarCard(title: "زيارات الموقع", unit: "زيارة", points: a.visitsByDay)
            BarCard(title: "الأعضاء الجدد", unit: "عضو", points: a.newByDay)
            EconCard(points: a.econByDay)
            HoursCard(values: a.byHour, peak: a.peaks.hour)
            DowCard(values: a.byDow, peak: a.peaks.dow, quiet: a.peaks.quietDow, names: Self.days)
            SourcesCard(items: a.sources, names: Self.sourceNames)
            if !a.topPages.isEmpty { PagesCard(pages: a.topPages) }

            HStack(spacing: 10) {
                mini("دخل المحافظ منذ البداية", Fmt.compact(Int(a.allTime.minted)))
                mini("صُرف بالمتجر منذ البداية", Fmt.compact(Int(a.allTime.spent)))
            }
        }
    }

    private func mini(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.content)
            Text(title).font(.caption).foregroundStyle(Theme.muted)
        }
        .card(radius: 18, padding: 14)
    }
}

/// بطاقة رقم + سهم التغيّر عن الفترة السابقة.
private struct Kpi: View {
    let title: String
    let symbol: String
    let t: StatTrend

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.gold)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Text(Fmt.compact(Int(t.value.rounded())))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.content)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            TrendBadge(t: t)
        }
        .card(radius: 18, padding: 14)
    }
}

private struct TrendBadge: View {
    let t: StatTrend

    var body: some View {
        if t.noPrev == true {
            Text("بداية السجل").font(.caption2).foregroundStyle(Theme.muted)
        } else if let p = t.pct {
            HStack(spacing: 3) {
                Image(systemName: p >= 0 ? "arrow.up.right" : "arrow.down.right")
                Text("\(abs(p))٪")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(p > 0 ? Color.green : (p < 0 ? Color.red : Theme.muted))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background((p > 0 ? Color.green : (p < 0 ? Color.red : Theme.muted)).opacity(0.14), in: Capsule())
        } else {
            Text("—").font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

/// تسميات المحور: عدد قليل موزّع بدل ٩٠ تسمية متراكبة.
private func ticks(_ labels: [String], count: Int = 5) -> [String] {
    guard labels.count > count else { return labels }
    let step = max(1, labels.count / count)
    return labels.enumerated().filter { $0.offset % step == 0 }.map(\.element)
}

private struct ChartFrame<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Theme.content)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Theme.gold)
                }
            }
            content
                .environment(\.layoutDirection, .leftToRight) // الزمن من اليسار لليمين مثل رسوم الموقع
        }
        .card()
    }
}

/// منحنى بلمسة: اسحب إصبعك على الرسم وتشوف قيمة اليوم.
private struct LineCard: View {
    let title: String
    let unit: String
    let points: [StatDay]
    @State private var selected: String?

    private var subtitle: String {
        if let s = selected, let p = points.first(where: { $0.label == s }) {
            return "\(s): \(Fmt.compact(Int(p.value))) \(unit)"
        }
        let avg = points.isEmpty ? 0 : points.map(\.value).reduce(0, +) / Double(points.count)
        return "المتوسط \(Fmt.compact(Int(avg.rounded()))) \(unit) يومياً"
    }

    var body: some View {
        ChartFrame(title: title, subtitle: subtitle) {
            Chart {
                ForEach(points) { p in
                    AreaMark(x: .value("اليوم", p.label), y: .value(unit, p.value))
                        .foregroundStyle(LinearGradient(colors: [Theme.gold.opacity(0.45), Theme.gold.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("اليوم", p.label), y: .value(unit, p.value))
                        .foregroundStyle(Theme.gold)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.catmullRom)
                }
                if let s = selected {
                    RuleMark(x: .value("اليوم", s))
                        .foregroundStyle(Theme.content.opacity(0.4))
                }
            }
            .chartXAxis {
                AxisMarks(values: ticks(points.map(\.label))) { _ in
                    AxisValueLabel().foregroundStyle(Theme.muted)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Theme.edge.opacity(0.6))
                    AxisValueLabel().foregroundStyle(Theme.muted)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in
                                    let x = v.location.x - geo[proxy.plotAreaFrame].origin.x
                                    if let label: String = proxy.value(atX: x), label != selected {
                                        selected = label
                                        Haptic.select()
                                    }
                                }
                                .onEnded { _ in selected = nil }
                        )
                }
            }
            .frame(height: 200)
        }
    }
}

private struct BarCard: View {
    let title: String
    let unit: String
    let points: [StatDay]

    var body: some View {
        let total = Int(points.map(\.value).reduce(0, +))
        ChartFrame(title: title, subtitle: "المجموع \(Fmt.compact(total)) \(unit)") {
            Chart(points) { p in
                BarMark(x: .value("اليوم", p.label), y: .value(unit, p.value))
                    .foregroundStyle(Theme.gold.gradient)
                    .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: ticks(points.map(\.label))) { _ in
                    AxisValueLabel().foregroundStyle(Theme.muted)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Theme.edge.opacity(0.6))
                    AxisValueLabel().foregroundStyle(Theme.muted)
                }
            }
            .frame(height: 170)
        }
    }
}

private struct EconCard: View {
    let points: [StatEcon]

    var body: some View {
        ChartFrame(title: "اقتصاد النقاط", subtitle: "دخل المحافظ مقابل الصرف بالمتجر") {
            Chart {
                ForEach(points) { p in
                    LineMark(x: .value("اليوم", p.label), y: .value("نقاط", p.minted), series: .value("النوع", "دخل"))
                        .foregroundStyle(by: .value("النوع", "دخل"))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("اليوم", p.label), y: .value("نقاط", p.sunk), series: .value("النوع", "صرف"))
                        .foregroundStyle(by: .value("النوع", "صرف"))
                        .interpolationMethod(.catmullRom)
                }
            }
            .chartForegroundStyleScale(["دخل": Color.green, "صرف": Color.red])
            .chartXAxis {
                AxisMarks(values: ticks(points.map(\.label))) { _ in
                    AxisValueLabel().foregroundStyle(Theme.muted)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Theme.edge.opacity(0.6))
                    AxisValueLabel().foregroundStyle(Theme.muted)
                }
            }
            .frame(height: 190)
        }
    }
}

private struct HoursCard: View {
    let values: [Double]
    let peak: Int?

    var body: some View {
        let sub = peak.map { "الذروة: الساعة \(StatsContent.hourName($0)) (بتوقيت الرياض)" } ?? "متوسط النشطين في كل ساعة"
        ChartFrame(title: "متى يتفاعلون؟", subtitle: sub) {
            Chart(Array(values.enumerated()), id: \.offset) { h, v in
                BarMark(x: .value("الساعة", h), y: .value("نشطين", v))
                    .foregroundStyle(h == peak ? AnyShapeStyle(Theme.gold) : AnyShapeStyle(Theme.gold.opacity(0.35)))
                    .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { v in
                    AxisValueLabel {
                        if let h = v.as(Int.self) { Text(StatsContent.hourName(h)) }
                    }
                    .foregroundStyle(Theme.muted)
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 150)
        }
    }
}

private struct DowCard: View {
    let values: [Double]
    let peak: Int?
    let quiet: Int?
    let names: [String]

    var body: some View {
        let sub: String = {
            var parts: [String] = []
            if let p = peak, p < names.count { parts.append("أنشط يوم: \(names[p])") }
            if let q = quiet, q < names.count { parts.append("الأهدأ: \(names[q])") }
            return parts.joined(separator: " · ")
        }()
        ChartFrame(title: "أيام الأسبوع", subtitle: sub.isEmpty ? nil : sub) {
            Chart(Array(values.enumerated()), id: \.offset) { d, v in
                BarMark(x: .value("اليوم", d < names.count ? names[d] : "\(d)"), y: .value("نشطين", v))
                    .foregroundStyle(d == peak ? AnyShapeStyle(Theme.gold) : AnyShapeStyle(Theme.gold.opacity(0.35)))
                    .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().foregroundStyle(Theme.muted) }
            }
            .chartYAxis(.hidden)
            .environment(\.layoutDirection, .rightToLeft)
            .frame(height: 150)
        }
    }
}

private struct SourcesCard: View {
    let items: [StatSource]
    let names: [String: String]

    var body: some View {
        let total = max(1, items.map(\.value).reduce(0, +))
        VStack(alignment: .leading, spacing: 12) {
            Text("من وين تجي النقاط").font(.headline).foregroundStyle(Theme.content)
            ForEach(items.sorted { $0.value > $1.value }.prefix(8), id: \.src) { s in
                let pct = s.value / total
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(names[s.src] ?? s.src)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.content)
                        Spacer()
                        Text("\(Int((pct * 100).rounded()))٪ · \(Fmt.compact(Int(s.value)))")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.surface2)
                            Capsule().fill(Theme.gold.gradient).frame(width: max(4, geo.size.width * pct))
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
        .card()
    }
}

private struct PagesCard: View {
    let pages: [StatPage]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("أكثر صفحات الموقع زيارة").font(.headline).foregroundStyle(Theme.content)
            ForEach(Array(pages.prefix(10).enumerated()), id: \.offset) { i, p in
                HStack(spacing: 10) {
                    Text("\(i + 1)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 20)
                    Text(p.path)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Theme.content)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .environment(\.layoutDirection, .leftToRight)
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(Fmt.compact(p.views))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.content)
                        Text("\(Fmt.compact(p.visitors)) زائر")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .card()
    }
}
