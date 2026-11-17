import LocalAuthentication
import SwiftUI

/// قفل Face ID: يفتح مرة، ويرجع يقفل لو طلعت من التطبيق أكثر من المهلة المختارة.
@MainActor
final class LockManager: ObservableObject {
    @Published private(set) var unlocked = false
    private var backgroundedAt: Date?
    private var authenticating = false

    static var biometryName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "رمز الجوال"
        }
    }

    static var biometrySymbol: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType == .touchID ? "touchid" : "faceid"
    }

    /// `deviceOwnerAuthentication` = الوجه أو البصمة، ولو فشلت يقبل رمز الجوال — فما تنحبس برّا تطبيقك.
    @discardableResult
    func authenticate(reason: String) async -> Bool {
        if authenticating { return false }
        authenticating = true
        defer { authenticating = false }
        let ctx = LAContext()
        ctx.localizedCancelTitle = "إلغاء"
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // جوال بلا رمز أصلاً: القفل ما له معنى، فلا نحبس المستخدم
            unlocked = true
            return true
        }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if ok { unlocked = true }
            return ok
        } catch {
            return false
        }
    }

    func didEnterBackground() {
        backgroundedAt = Date()
    }

    func didBecomeActive(grace: Int) {
        guard let at = backgroundedAt else { return }
        backgroundedAt = nil
        if Date().timeIntervalSince(at) >= Double(grace) {
            unlocked = false
        }
    }
}

struct LockView: View {
    var title: String
    var unlock: () -> Void

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Theme.gold)
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.content)
                Button(action: unlock) {
                    Label("افتح بـ" + LockManager.biometryName, systemImage: LockManager.biometrySymbol)
                        .font(.headline)
                        .foregroundStyle(Theme.goldText)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Theme.gold, in: Capsule())
                }
                .padding(.top, 4)
            }
            .padding(24)
        }
    }
}

/// غطاء يخفي المحتوى في شاشة تبديل التطبيقات لما يكون القفل مفعّل.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            Image("LaunchLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 167, height: 64)
        }
    }
}
