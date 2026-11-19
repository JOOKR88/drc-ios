import BackgroundTasks
import Security
import SwiftUI
import UserNotifications

// MARK: - البيانات (نفس رد /api/notifications في الموقع)

struct NotifItem: Codable, Identifiable, Hashable {
    let id: String
    let category: String
    let critical: Bool
    let title: String
    let body: String?
    let href: String?
    let unread: Bool
    let pinned: Bool
    let when: String
}

struct NotifResponse: Codable {
    let unread: Int
    let hidden: [String]?
    let pushHidden: [String]?
    let items: [NotifItem]
}

enum NotifCategory {
    static let all: [(key: String, label: String, symbol: String)] = [
        ("moderation", "الإشراف", "shield.lefthalf.filled"),
        ("tickets", "التذاكر والمنشن", "ticket.fill"),
        ("orders", "الطلبات", "shippingbox.fill"),
        ("purchases", "المشتريات", "bag.fill"),
        ("points", "النقاط والتحويلات", "sparkles"),
        ("suggestions", "الاقتراحات", "lightbulb.fill"),
    ]

    static func symbol(_ key: String) -> String {
        all.first { $0.key == key }?.symbol ?? "bell.fill"
    }
}

enum NotifKey {
    static let pushEnabled = "pushEnabled"
    static let badgeEnabled = "badgeEnabled"
    static let seen = "notifSeen"
}

/// كوكي الجلسة نسخة في سلسلة المفاتيح: الفحص في الخلفية يشتغل بدون متصفح التطبيق.
enum Keychain {
    private static func base(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "org.dreamerc.app",
         kSecAttrAccount as String: key]
    }

    static func set(_ value: String?, for key: String) {
        SecItemDelete(base(key) as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = base(key)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        var q = base(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - المخزن

@MainActor
final class NotificationsStore: ObservableObject {
    static let shared = NotificationsStore()

    @Published private(set) var items: [NotifItem] = []
    @Published private(set) var hidden: [String] = []
    @Published private(set) var pushHidden: [String] = []
    @Published private(set) var loaded = false

    private init() {
        if let r = DiskCache.decode(NotifResponse.self, "notifications") { apply(r, cache: nil) }
    }

    func apply(_ r: NotifResponse, cache data: Data?) {
        withAnimation(.snappy) {
            items = r.items
            hidden = r.hidden ?? []
            pushHidden = r.pushHidden ?? []
        }
        loaded = true
        AccountStore.shared.setUnread(r.unread)
        if let data { DiskCache.write("notifications", data) }
    }

    func load() async {
        guard let d = try? await API.get("/api/notifications?limit=50"),
              let r = try? JSONDecoder().decode(NotifResponse.self, from: d) else { return }
        apply(r, cache: d)
        await NotifPoller.updateBadge(r.unread)
    }

    private func post(_ body: [String: Any]) async {
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        _ = try? await API.request("/api/notifications", method: "POST", body: data)
    }

    func markRead(_ id: String) async {
        if let i = items.firstIndex(where: { $0.id == id }), items[i].unread {
            let it = items[i]
            items[i] = NotifItem(id: it.id, category: it.category, critical: it.critical, title: it.title, body: it.body,
                                 href: it.href, unread: false, pinned: it.pinned, when: it.when)
        }
        await post(["id": id])
        await load()
    }

    func markAll() async {
        Haptic.tap()
        await post(["all": true])
        await load()
    }

    /// نفس إعداد الموقع (علامات الجرس / علامات الجوال) — يُحفظ في الحساب.
    func setHidden(_ keys: [String]) async {
        hidden = keys
        await post(["hidden": keys])
        await load()
    }

    func setPushHidden(_ keys: [String]) async {
        pushHidden = keys
        await post(["pushHidden": keys])
        await load()
    }
}

// MARK: - الفحص والإشعارات المحلية

/// بدون حساب Apple المدفوع ما فيه Push من السيرفر — فالتطبيق نفسه يشيّك:
/// كل دقيقة وهو مفتوح، وفي الخلفية متى ما سمح iOS (Background App Refresh)، ويطلع الجديد إشعاراً محلياً.
@MainActor
enum NotifPoller {
    static let taskID = "org.dreamerc.app.refresh"

    static func schedule() {
        let req = BGAppRefreshTaskRequest(identifier: taskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    static var pushEnabled: Bool { UserDefaults.standard.bool(forKey: NotifKey.pushEnabled) }

    static var badgeEnabled: Bool {
        UserDefaults.standard.object(forKey: NotifKey.badgeEnabled) == nil ? true : UserDefaults.standard.bool(forKey: NotifKey.badgeEnabled)
    }

    @discardableResult
    static func check(background: Bool) async -> Bool {
        guard AccountStore.shared.loggedIn != false || background else { return false }
        guard let d = try? await API.request("/api/notifications?limit=30", storedCookie: background),
              let r = try? JSONDecoder().decode(NotifResponse.self, from: d) else { return false }
        NotificationsStore.shared.apply(r, cache: d)

        let defaults = UserDefaults.standard
        let firstRun = defaults.object(forKey: NotifKey.seen) == nil
        let seen = Set(defaults.stringArray(forKey: NotifKey.seen) ?? [])
        let fresh = r.items.filter { $0.unread && !seen.contains($0.id) }
        // أول تشغيل: ما نطلّع كل القديم دفعة وحدة — نعتبره مشاهَداً
        if !firstRun && pushEnabled {
            let muted = Set(r.pushHidden ?? [])
            for item in fresh.prefix(5) where !muted.contains(item.category) {
                post(item)
            }
        }
        let merged = Array((r.items.map(\.id) + Array(seen)).prefix(400))
        defaults.set(merged, forKey: NotifKey.seen)
        await updateBadge(r.unread)
        return true
    }

    private static func post(_ item: NotifItem) {
        let c = UNMutableNotificationContent()
        c.title = item.title
        if let b = item.body, !b.isEmpty { c.body = b }
        c.sound = .default
        c.threadIdentifier = item.category
        c.userInfo = ["href": item.href ?? "/notifications", "id": item.id]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: item.id, content: c, trigger: nil))
    }

    static func updateBadge(_ unread: Int) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.badgeSetting == .enabled else { return }
        try? await center.setBadgeCount(badgeEnabled ? unread : 0)
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}

// MARK: - الشاشات

struct NotificationsView: View {
    @ObservedObject private var store = NotificationsStore.shared
    @State private var onlyUnread = false
    @State private var pushed: Route?
    @State private var showPushed = false
    @State private var external: IdentifiableURL?

    private var shown: [NotifItem] { onlyUnread ? store.items.filter(\.unread) : store.items }

    var body: some View {
        List {
            Section {
                Picker("العرض", selection: $onlyUnread) {
                    Text("الكل").tag(false)
                    Text("غير المقروء").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if store.loaded && shown.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(Theme.gold)
                        Text(onlyUnread ? "ما عندك تنبيهات غير مقروءة." : "ما فيه تنبيهات بعد.")
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .listRowBackground(Color.clear)
                }
            }
            Section {
                ForEach(shown) { item in
                    Button { open(item) } label: { NotifRow(item: item) }
                        .listRowBackground(item.unread ? Theme.gold.opacity(0.08) : Theme.surface)
                        .swipeActions(edge: .leading) {
                            if item.unread {
                                Button {
                                    Task { await store.markRead(item.id) }
                                } label: { Label("قُرئ", systemImage: "checkmark") }
                                .tint(Theme.gold)
                            }
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("التنبيهات")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await store.markAll() }
                } label: { Image(systemName: "checkmark.circle") }
            }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: Route.notificationSettings) { Image(systemName: "gearshape") }
            }
        }
        .refreshable { await store.load() }
        .task { await store.load() }
        .navigationDestination(isPresented: $showPushed) {
            if let pushed { RouteDestination(route: pushed) }
        }
        .sheet(item: $external) { item in SafariView(url: item.url).ignoresSafeArea() }
    }

    private func open(_ item: NotifItem) {
        Haptic.tap()
        Task { await store.markRead(item.id) }
        guard let href = item.href, !href.isEmpty else { return }
        if href.hasPrefix("http"), let url = URL(string: href), url.host != AppConfig.host {
            external = IdentifiableURL(url: url)
            return
        }
        pushed = Route.forPath(href, title: item.title)
        showPushed = true
    }
}

private struct NotifRow: View {
    let item: NotifItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: NotifCategory.symbol(item.category))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(item.critical ? Color.white : Theme.gold)
                .frame(width: 36, height: 36)
                .background(item.critical ? AnyShapeStyle(Color.red.gradient) : AnyShapeStyle(Theme.surface2), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.title)
                        .font(.subheadline.weight(item.unread ? .bold : .regular))
                        .foregroundStyle(Theme.content)
                        .multilineTextAlignment(.leading)
                    if item.pinned {
                        Image(systemName: "pin.fill").font(.caption2).foregroundStyle(Theme.gold)
                    }
                }
                if let b = item.body, !b.isEmpty {
                    Text(b)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Text(item.when).font(.caption2).foregroundStyle(Theme.muted.opacity(0.8))
            }
            Spacer(minLength: 4)
            if item.unread {
                Circle().fill(Theme.gold).frame(width: 9, height: 9).padding(.top, 6)
            }
        }
        .padding(.vertical, 4)
    }
}

struct NotificationSettingsView: View {
    @ObservedObject private var store = NotificationsStore.shared
    @AppStorage(NotifKey.pushEnabled) private var pushEnabled = false
    @AppStorage(NotifKey.badgeEnabled) private var badgeEnabled = true
    @State private var denied = false

    var body: some View {
        Form {
            Section {
                Toggle("إشعارات على الجوال", isOn: pushBinding)
                Toggle("عدّاد على أيقونة التطبيق", isOn: $badgeEnabled)
                if denied {
                    Button("افتح إعدادات iOS وفعّل الإشعارات لـ DRC") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .foregroundStyle(Theme.gold)
                }
            } footer: {
                Text("التطبيق يشيّك على تنبيهاتك ويطلعها إشعاراً: كل دقيقة وهو مفتوح، وفي الخلفية متى ما سمح iOS (عادة كل ربع ساعة لساعات حسب استخدامك) — فما تكون لحظية مثل إشعارات الحساب المدفوع. خلّ «تحديث التطبيقات في الخلفية» شغّال لـ DRC.")
            }

            Section {
                ForEach(NotifCategory.all, id: \.key) { c in
                    Toggle(isOn: binding(c.key, in: store.hidden) { await store.setHidden($0) }) {
                        Label(c.label, systemImage: c.symbol)
                    }
                }
            } header: {
                Text("تظهر في الجرس")
            }

            Section {
                ForEach(NotifCategory.all, id: \.key) { c in
                    Toggle(isOn: binding(c.key, in: store.pushHidden) { await store.setPushHidden($0) }) {
                        Label(c.label, systemImage: c.symbol)
                    }
                }
            } header: {
                Text("توصل للجوال")
            } footer: {
                Text("نفس إعدادات صفحة التنبيهات في الموقع — تنحفظ في حسابك.")
            }
        }
        .tint(Theme.gold)
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("إعدادات التنبيهات")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.load()
            let s = await UNUserNotificationCenter.current().notificationSettings()
            denied = s.authorizationStatus == .denied
        }
        .onChange(of: badgeEnabled) { _ in
            Task { await NotifPoller.updateBadge(AccountStore.shared.unread) }
        }
    }

    private var pushBinding: Binding<Bool> {
        Binding(
            get: { pushEnabled },
            set: { on in
                Task { @MainActor in
                    if on {
                        let ok = await NotifPoller.requestPermission()
                        denied = !ok
                        pushEnabled = ok
                        if ok {
                            NotifPoller.schedule()
                            await NotifPoller.check(background: false)
                        }
                    } else {
                        pushEnabled = false
                    }
                }
            }
        )
    }

    /// مفتاح «مفعّل» = النوع غير موجود في قائمة المخفي.
    private func binding(_ key: String, in list: [String], save: @escaping ([String]) async -> Void) -> Binding<Bool> {
        Binding(
            get: { !list.contains(key) },
            set: { on in
                var next = list.filter { $0 != key }
                if !on { next.append(key) }
                Task { @MainActor in await save(next) }
            }
        )
    }
}
