import SwiftUI

/// مكتبة Souls الأصلية: مختارات، تصفية بالألعاب، بحث لحظي محلي، وكل شي يفتح من الكاش بدون نت.
struct SoulsView: View {
    @ObservedObject private var store = SoulsStore.shared
    @State private var game: String?
    @State private var query = ""
    @State private var path = NavigationPath()
    @State private var openedLaunchArticle = false

    private var articles: [ArticleSummary] { store.index?.articles ?? [] }

    private var filtered: [ArticleSummary] {
        var list = articles
        if let game { list = list.filter { $0.game == game } }
        let q = normalizeArabic(query.trimmingCharacters(in: .whitespaces))
        if !q.isEmpty {
            list = list.filter { normalizeArabic($0.title + " " + $0.excerpt).contains(q) }
        }
        return list
    }

    private var featured: [ArticleSummary] {
        Array(articles.filter { $0.image != nil }.prefix(6))
    }

    private var latest: [ArticleSummary] {
        Array(articles.sorted { $0.createdAt > $1.createdAt }.prefix(10))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if store.index == nil {
                        Skeleton(height: 240, radius: 26)
                        ForEach(0..<5, id: \.self) { _ in Skeleton(height: 76, radius: 18) }
                    } else {
                        if query.isEmpty && game == nil && !featured.isEmpty {
                            FeaturedPager(items: featured)
                        }
                        GameChips(games: store.index?.games ?? [], selected: $game)
                        if query.isEmpty && game == nil {
                            SectionTitle(title: "الأحدث")
                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 12) {
                                    ForEach(latest) { a in
                                        NavigationLink(value: Route.article(slug: a.slug)) { SmallCard(a: a) }
                                            .buttonStyle(PressableStyle())
                                    }
                                }
                            }
                            .scrollIndicators(.hidden)
                            SectionTitle(title: "الأكثر قراءة")
                        }
                        LazyVStack(spacing: 10) {
                            ForEach(query.isEmpty && game == nil ? Array(articles.prefix(30)) : filtered) { a in
                                NavigationLink(value: Route.article(slug: a.slug)) { ArticleRow(a: a) }
                                    .buttonStyle(PressableStyle())
                            }
                            if (game != nil || !query.isEmpty) && filtered.isEmpty {
                                Text("ما فيه مقالات مطابقة.")
                                    .foregroundStyle(Theme.muted)
                                    .padding(.top, 20)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Souls")
            .searchable(text: $query, prompt: "ابحث في المقالات")
            .refreshable { await store.loadIndex(force: true) }
            .task {
                await store.loadIndex()
                // لقطات GitHub: `-article <slug>` يفتح مقالاً مباشرة
                if !openedLaunchArticle, let slug = UserDefaults.standard.string(forKey: "article"), !slug.isEmpty {
                    openedLaunchArticle = true
                    path.append(Route.article(slug: slug))
                }
            }
            .navigationDestination(for: Route.self) { RouteDestination(route: $0) }
        }
    }
}

private struct FeaturedPager: View {
    let items: [ArticleSummary]
    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, a in
                NavigationLink(value: Route.article(slug: a.slug)) {
                    ZStack(alignment: .bottomLeading) {
                        RemoteImage(url: a.image)
                        LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .center, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 6) {
                            GameBadge(key: a.game)
                            Text(a.title)
                                .font(.title3.weight(.heavy))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(18)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: 250)
    }
}

private struct GameChips: View {
    let games: [SoulsGame]
    @Binding var selected: String?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip("الكل", nil, Theme.gold)
                ForEach(games) { g in chip(g.name, g.key, Color(hex: g.accent)) }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ title: String, _ key: String?, _ color: Color) -> some View {
        let on = selected == key
        return Button {
            Haptic.select()
            withAnimation(.snappy) { selected = key }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? Theme.goldText : Theme.content)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(on ? AnyShapeStyle(color) : AnyShapeStyle(Theme.surface2), in: Capsule())
                .overlay(Capsule().stroke(on ? Color.clear : Theme.edge, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }
}

struct GameBadge: View {
    let key: String
    @ObservedObject private var store = SoulsStore.shared

    var body: some View {
        let g = store.game(key)
        Text(g?.name ?? key)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(hex: g?.accent ?? "#888888").opacity(0.85), in: Capsule())
    }
}

private struct SmallCard: View {
    let a: ArticleSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImage(url: a.image)
                .frame(width: 170, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(a.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.content)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: 170, alignment: .leading)
        }
    }
}

private struct ArticleRow: View {
    let a: ArticleSummary

    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: a.image)
                .frame(width: 92, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(a.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.content)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 8) {
                    GameBadge(key: a.game)
                    Label(Fmt.n(a.views), systemImage: "eye")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.edge.opacity(0.7), lineWidth: 1))
    }
}
