import SafariServices
import SwiftUI

/// خط تحميل رفيع بلون الهوية أعلى الشاشة.
struct ProgressLine: View {
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Theme.gold)
                .frame(width: geo.size.width * max(0.06, min(progress, 1)), height: 2)
                .animation(.easeOut(duration: 0.2), value: progress)
        }
        .frame(height: 2)
        .allowsHitTesting(false)
    }
}

/// بدل الصفحة البيضاء أو رسالة خطأ المتصفح لما ينقطع النت.
struct OfflineView: View {
    var retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.gold)
            Text("ما فيه اتصال")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.content)
            Text("تأكد من الإنترنت وحاول مرة ثانية.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            Button(action: retry) {
                Text("إعادة المحاولة")
                    .font(.headline)
                    .foregroundStyle(Theme.goldText)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Theme.gold, in: Capsule())
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
    }
}

/// نفس شاشة الإطلاق (اللون والشعار بنفس المقاس) فما يحس المستخدم بقفزة،
/// وتبقى لين تجهز أول صفحة.
struct SplashView: View {
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

/// الروابط الخارجية: سفاري داخل التطبيق، فترجع بسحبة بدون ما تطلع من التطبيق.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = Theme.goldUI
        vc.preferredBarTintColor = Theme.surfaceUI
        vc.dismissButtonStyle = .close
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
