import SwiftUI
import WidgetKit

struct StatsEntry: TimelineEntry {
    enum State { case ok, needsLogin, offline }
    let date: Date
    let stats: WidgetStats
    let state: State
}

struct StatsProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatsEntry {
        StatsEntry(date: Date(), stats: .sample, state: .ok)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatsEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task { completion(await load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatsEntry>) -> Void) {
        Task {
            let entry = await load()
            // iOS يحدد التوقيت الفعلي؛ نطلب تحديثاً كل نصف ساعة تقريباً
            let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func cached() -> WidgetStats? {
        guard let data = WidgetStore.lastStats else { return nil }
        return try? JSONDecoder().decode(WidgetStats.self, from: data)
    }

    private func load() async -> StatsEntry {
        guard let token = WidgetStore.token, !token.isEmpty,
              let url = URL(string: "https://dreamerc.org/api/app/widget") else {
            return StatsEntry(date: Date(), stats: cached() ?? .sample, state: .needsLogin)
        }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 {
                return StatsEntry(date: Date(), stats: cached() ?? .sample, state: .needsLogin)
            }
            let stats = try JSONDecoder().decode(WidgetStats.self, from: data)
            WidgetStore.lastStats = data
            return StatsEntry(date: Date(), stats: stats, state: .ok)
        } catch {
            // بلا نت: نعرض آخر أرقام محفوظة مع إشارة إنها قديمة
            return StatsEntry(date: Date(), stats: cached() ?? .sample, state: cached() == nil ? .needsLogin : .offline)
        }
    }
}

// MARK: - الشكل

private enum W {
    static let bg = Color(red: 11 / 255, green: 10 / 255, blue: 9 / 255)
    static let surface = Color(red: 20 / 255, green: 18 / 255, blue: 16 / 255)
    static let gold = Color(red: 204 / 255, green: 191 / 255, blue: 174 / 255)
    static let content = Color(red: 240 / 255, green: 236 / 255, blue: 229 / 255)
    static let muted = Color(red: 145 / 255, green: 137 / 255, blue: 125 / 255)
    static let green = Color(red: 0.36, green: 0.78, blue: 0.47)
    static let red = Color(red: 0.92, green: 0.36, blue: 0.33)

    static func num(_ n: Int?) -> String {
        guard let n else { return "—" }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        func short(_ x: Double, _ suffix: String) -> String {
            f.maximumFractionDigits = x >= 100 ? 0 : 1
            return (f.string(from: NSNumber(value: x)) ?? "\(n)") + suffix
        }
        if n >= 1_000_000 { return short(Double(n) / 1_000_000, "M") }
        if n >= 10_000 { return short(Double(n) / 1000, "K") }
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

private struct Stat: View {
    let title: String
    let value: String
    var accent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(accent ? W.gold : W.content)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(W.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Header: View {
    let entry: StatsEntry

    var body: some View {
        HStack(spacing: 6) {
            Text("DRC")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(W.gold)
            Spacer(minLength: 4)
            switch entry.state {
            case .needsLogin:
                Text("افتح التطبيق").font(.system(size: 10)).foregroundStyle(W.muted)
            case .offline:
                Image(systemName: "wifi.slash").font(.system(size: 10)).foregroundStyle(W.muted)
            case .ok:
                HStack(spacing: 4) {
                    Circle().fill(entry.stats.botOk ? W.green : W.red).frame(width: 6, height: 6)
                    Text(entry.stats.botOk ? "البوت شغّال" : "البوت واقف")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(W.muted)
                }
            }
        }
    }
}

struct DRCWidgetView: View {
    let entry: StatsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .environment(\.layoutDirection, .rightToLeft)
            .widgetURL(URL(string: "drc-app://open/dashboard"))
            .modifier(WidgetBackground())
    }

    @ViewBuilder private var content: some View {
        let s = entry.stats
        if family == .systemSmall {
            VStack(alignment: .leading, spacing: 8) {
                Header(entry: entry)
                Spacer(minLength: 0)
                Stat(title: "أعضاء السيرفر", value: W.num(s.members))
                Stat(title: "طلبات آرك جديدة", value: W.num(s.arkNew), accent: s.arkNew > 0)
            }
            .padding(2)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Header(entry: entry)
                Spacer(minLength: 0)
                HStack(alignment: .top, spacing: 8) {
                    Stat(title: "أعضاء السيرفر", value: W.num(s.members))
                    Stat(
                        title: "نشطين ٧ أيام" + (s.growthPct.map { $0 >= 0 ? " ↑\($0)%" : " ↓\(-$0)%" } ?? ""),
                        value: W.num(s.active7d)
                    )
                }
                HStack(alignment: .top, spacing: 8) {
                    Stat(title: "زوار الموقع ٧ أيام", value: W.num(s.visits7d))
                    Stat(
                        title: "آرك: جديد · قيد التنفيذ",
                        value: "\(W.num(s.arkNew)) · \(W.num(s.arkActive))",
                        accent: s.arkNew > 0
                    )
                }
            }
            .padding(2)
        }
    }
}

/// خلفية الودجت: iOS 17+ يطلب containerBackground، وما قبله خلفية عادية.
private struct WidgetBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.containerBackground(for: .widget) {
                LinearGradient(colors: [W.surface, W.bg], startPoint: .top, endPoint: .bottom)
            }
        } else {
            content
                .padding()
                .background(LinearGradient(colors: [W.surface, W.bg], startPoint: .top, endPoint: .bottom))
        }
    }
}

struct DRCStatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DRCStats", provider: StatsProvider()) { entry in
            DRCWidgetView(entry: entry)
        }
        .configurationDisplayName("أرقام DRC")
        .description("أعضاء السيرفر والنشاط والزوار وطلبات آرك.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct DRCWidgetBundle: WidgetBundle {
    var body: some Widget {
        DRCStatsWidget()
    }
}
