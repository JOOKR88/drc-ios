import SwiftUI

extension Theme {
    static let surface2 = Color(red: 28 / 255, green: 26 / 255, blue: 23 / 255)
    static let edge = Color(uiColor: edgeUI)
    /// الشامبين المعدني: نفس تدرّج زر الهوية في الموقع
    static let champagne = LinearGradient(
        colors: [Color(red: 0.88, green: 0.83, blue: 0.76), Color(red: 0.72, green: 0.66, blue: 0.58)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// صورة من الشبكة بخلفية بلون السطح أثناء التحميل وظهور ناعم (الكاش من URLCache).
struct RemoteImage: View {
    let url: String?

    var body: some View {
        if let u = Fmt.absolute(url) {
            AsyncImage(url: u, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill().transition(.opacity)
                } else {
                    Theme.surface2
                }
            }
        } else {
            Theme.surface2
        }
    }
}

struct Avatar: View {
    let url: String?
    var size: CGFloat = 40
    var ring: Color = Theme.edge

    var body: some View {
        RemoteImage(url: url)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(ring, lineWidth: 1.5))
    }
}

/// بطاقة المحتوى: سطح داكن بحد خفيف وزوايا iOS المنحنية.
struct CardStyle: ViewModifier {
    var radius: CGFloat = 22
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.surface2, Theme.surface], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.edge.opacity(0.8), lineWidth: 1)
            )
    }
}

/// زجاج iOS 26 للعناصر العائمة، ومادة ضبابية على ما قبله.
struct FloatingGlass: ViewModifier {
    var radius: CGFloat = 24

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

extension View {
    func card(radius: CGFloat = 22, padding: CGFloat = 16) -> some View {
        modifier(CardStyle(radius: radius, padding: padding))
    }

    func floatingGlass(radius: CGFloat = 24) -> some View {
        modifier(FloatingGlass(radius: radius))
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.content)
            if let subtitle {
                Text(subtitle).font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// هيكل تحميل نابض بدل الشاشة الفاضية.
struct Skeleton: View {
    var height: CGFloat
    var radius: CGFloat = 22
    @State private var on = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Theme.surface2)
            .frame(height: height)
            .opacity(on ? 0.45 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

/// اهتزاز خفيف مع اللمس — يُستعمل في الأزرار والبطاقات.
enum Haptic {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
}

/// ضغطة البطاقات: تصغير بسيط بحركة زنبركية مثل تطبيقات iOS.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
