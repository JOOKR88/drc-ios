import SwiftUI

/// إعدادات التطبيق: كل ميزة إضافية تنطفي وتشتغل من هنا (تنفتح من أيقونة المنزلقات في رأس الموقع
/// أو من اختصار الأيقونة).
struct SettingsView: View {
    @AppStorage(SettingKey.dashboardTab) private var dashboardTab = true
    @AppStorage(SettingKey.quickActions) private var quickActions = true
    @AppStorage(SettingKey.lockEnabled) private var lockEnabled = false
    @AppStorage(SettingKey.lockScope) private var lockScope = LockScope.dashboard.rawValue
    @AppStorage(SettingKey.lockGrace) private var lockGrace = 60

    @EnvironmentObject private var lock: LockManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("تبويب لوحة التحكم", isOn: $dashboardTab)
                } footer: {
                    Text("يظهر في الشريط السفلي مكان المتجر، لأن iOS يعرض خمس تبويبات بحد أقصى. المتجر يبقى من الرئيسية وحسابي.")
                }

                Section {
                    Toggle("اختصارات الأيقونة", isOn: $quickActions)
                } footer: {
                    Text("ضغطة مطوّلة على أيقونة DRC: لوحة التحكم، طلبات آرك، التنبيهات، إعدادات التطبيق.")
                }

                Section {
                    Toggle("قفل بـ" + LockManager.biometryName, isOn: lockBinding)
                    if lockEnabled {
                        Picker("يقفل", selection: $lockScope) {
                            Text("لوحة التحكم فقط").tag(LockScope.dashboard.rawValue)
                            Text("التطبيق كامل").tag(LockScope.app.rawValue)
                        }
                        .disabled(!lock.unlocked)
                        Picker("يرجع القفل بعد الخروج", selection: $lockGrace) {
                            Text("فوراً").tag(0)
                            Text("دقيقة").tag(60)
                            Text("٥ دقائق").tag(300)
                            Text("١٥ دقيقة").tag(900)
                        }
                        .disabled(!lock.unlocked)
                    }
                } footer: {
                    Text("تشغيل القفل أو إطفاؤه يطلب " + LockManager.biometryName + " — فما يقدر أحد يطفيه من جوالك بدونك. ولو ما تعرّف عليك يقبل رمز الجوال.")
                }

                Section {
                    LabeledContent("الحالة", value: WidgetBridge.isLinked ? "مربوط بحسابك" : "سجّل دخول بحساب الأونر")
                    Button("تحديث الودجت الآن") { WidgetBridge.reload() }
                } header: {
                    Text("الودجت")
                } footer: {
                    Text("أضفه من الشاشة الرئيسية: ضغطة مطوّلة ← تعديل ← إضافة ودجت ← DRC. تقدر تشيله بنفس الطريقة.")
                }

                Section {
                    LabeledContent("الإصدار", value: version)
                }
            }
            .tint(Theme.gold)
            .navigationTitle("إعدادات التطبيق")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
        }
    }

    private var lockBinding: Binding<Bool> {
        Binding(
            get: { lockEnabled },
            set: { on in
                Task { @MainActor in
                    let reason = on ? "تفعيل قفل التطبيق" : "إيقاف قفل التطبيق"
                    if await lock.authenticate(reason: reason) {
                        lockEnabled = on
                    }
                }
            }
        )
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
