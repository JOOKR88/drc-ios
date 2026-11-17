import SwiftUI

struct LeaderboardView: View {
    @ObservedObject private var store = LeaderboardStore.shared
    @State private var board = "xp"
    @State private var query = ""
    @State private var results: [LbRow]?
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?

    private let boards: [(String, String)] = [("xp", "XP"), ("rich", "الأغنى"), ("rep", "السمعة"), ("week", "الأسبوعي")]

    private var unit: String {
        switch board {
        case "rich": return "نقطة"
        case "rep": return "سمعة"
        case "week": return "هذا الأسبوع"
        default: return "XP"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    Picker("اللوحة", selection: $board) {
                        ForEach(boards, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 6)

                    if let results {
                        if searching && results.isEmpty {
                            ProgressView().tint(Theme.gold).padding(.top, 30)
                        } else if results.isEmpty {
                            Text("ما فيه نتيجة لـ «\(query)».")
                                .foregroundStyle(Theme.muted)
                                .padding(.top, 30)
                        }
                        ForEach(results) { row in
                            link(row) { LbRowView(row: row, unit: "XP") }
                        }
                    } else if let data = store.data[board] {
                        if data.rows.count >= 3 {
                            Podium(rows: Array(data.rows.prefix(3)), unit: unit)
                                .id(board)
                                .padding(.bottom, 8)
                        }
                        ForEach(data.rows.dropFirst(min(3, data.rows.count))) { row in
                            link(row) { LbRowView(row: row, unit: unit) }
                        }
                    } else {
                        Skeleton(height: 220, radius: 26)
                        ForEach(0..<6, id: \.self) { _ in Skeleton(height: 62, radius: 18) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 90)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("المتصدرون")
            .searchable(text: $query, prompt: "ابحث بالاسم أو الـ ID")
            .onChange(of: query) { q in runSearch(q) }
            .onChange(of: board) { _ in Haptic.select() }
            .refreshable { await store.load(board, force: true) }
            .task(id: board) { await store.load(board) }
            .safeAreaInset(edge: .bottom) {
                if results == nil, let me = store.data[board]?.me {
                    MyRankBar(me: me)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }
            }
            .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
        }
    }

    @ViewBuilder
    private func link<Content: View>(_ row: LbRow, @ViewBuilder content: () -> Content) -> some View {
        if let id = row.userId {
            NavigationLink(value: Route.web(path: "/u/" + id, title: row.name)) { content() }
                .buttonStyle(PressableStyle())
        } else {
            content()
        }
    }

    private func runSearch(_ q: String) {
        searchTask?.cancel()
        let text = q.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else {
            withAnimation(.snappy) { results = nil }
            return
        }
        searching = true
        if results == nil { results = [] }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            let rows = await store.search(text)
            if Task.isCancelled { return }
            withAnimation(.snappy) {
                results = rows
                searching = false
            }
        }
    }
}

private struct LbRowView: View {
    let row: LbRow
    let unit: String

    var body: some View {
        let me = row.isMe == true
        HStack(spacing: 12) {
            Text(row.rank > 0 ? "\(row.rank)" : "—")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.muted)
                .frame(width: 34)
            Avatar(url: row.avatar, size: 42, ring: me ? Theme.gold : Theme.edge)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.content)
                        .lineLimit(1)
                    if me {
                        Text("أنت")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.goldText)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.gold, in: Capsule())
                    }
                }
                if let total = row.total {
                    Text("رصيد " + Fmt.n(total))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text(Fmt.n(row.points))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.content)
                Text(unit).font(.caption2).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(me ? Theme.gold.opacity(0.12) : Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(me ? Theme.gold.opacity(0.7) : Theme.edge.opacity(0.7), lineWidth: 1)
        )
    }
}

/// منصّة الثلاثة الأوائل: الأول بالوسط أعلى، وتطلع بحركة زنبركية متتابعة.
private struct Podium: View {
    let rows: [LbRow]
    let unit: String
    @State private var shown = false

    private static let colors: [Color] = [
        Color(red: 0.86, green: 0.76, blue: 0.48),
        Color(red: 0.78, green: 0.78, blue: 0.80),
        Color(red: 0.78, green: 0.55, blue: 0.36),
    ]

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            spot(1, height: 86)
            spot(0, height: 116)
            spot(2, height: 70)
        }
        .padding(.top, 18)
        .onAppear {
            shown = false
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { shown = true }
        }
    }

    @ViewBuilder
    private func spot(_ i: Int, height: CGFloat) -> some View {
        let r = rows[i]
        let color = Self.colors[i]
        VStack(spacing: 8) {
            ZStack(alignment: .top) {
                Avatar(url: r.avatar, size: i == 0 ? 82 : 64, ring: color)
                    .shadow(color: color.opacity(0.45), radius: 12)
                if i == 0 {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(color)
                        .offset(y: -24)
                }
            }
            Text(r.name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.content)
                .lineLimit(1)
            Text(Fmt.n(r.points))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.06)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    Text("\(i + 1)")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(color.opacity(0.9))
                )
                .frame(height: shown ? height : 0)
        }
        .frame(maxWidth: .infinity)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 30)
        .animation(.spring(response: 0.6, dampingFraction: 0.75).delay(Double(i) * 0.08), value: shown)
    }
}

private struct MyRankBar: View {
    let me: LeaderboardResponse.Me

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.gold)
            VStack(alignment: .leading, spacing: 0) {
                Text("ترتيبك عالمياً")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                Text("#" + Fmt.n(me.rank))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.content)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("المستوى \(me.level)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.content)
                Text(Fmt.n(me.xp) + " XP")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .floatingGlass(radius: 22)
    }
}
