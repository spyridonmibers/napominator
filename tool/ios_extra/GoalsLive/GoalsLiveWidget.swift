import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Оформление

private let brandGradient = LinearGradient(
    colors: [Color(hex: "#FF6366F1"), Color(hex: "#FFA855F7")],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

extension Color {
    /// "#AARRGGBB" или "#RRGGBB".
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let a, r, g, b: Double
        if s.count == 8 {
            a = Double((v >> 24) & 0xFF) / 255
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
        } else {
            a = 1
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

struct ProgressRingView: View {
    let done: Int
    let total: Int
    var lineWidth: CGFloat = 3

    var body: some View {
        let p = total == 0 ? 0 : Double(done) / Double(total)
        ZStack {
            Circle().stroke(Color.white.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: p)
                .stroke(brandGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct CheckMark: View {
    let item: GoalItem

    var body: some View {
        let icon = Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(item.done ? Color(hex: item.color) : Color.white.opacity(0.55))
        if #available(iOS 17.0, *) {
            Button(intent: ToggleGoalIntent(goalId: item.id)) { icon }
                .buttonStyle(.plain)
        } else {
            icon
        }
    }
}

struct GoalRowView: View {
    let item: GoalItem

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: item.color))
                .frame(width: 10, height: 10)
            Text(item.title)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(item.done ? Color.white.opacity(0.5) : Color.white)
                .strikethrough(item.done, color: Color.white.opacity(0.5))
            Spacer(minLength: 6)
            CheckMark(item: item)
        }
    }
}

private func headline(_ s: GoalsActivityAttributes.ContentState) -> String {
    let left = s.total - s.done
    return left == 0 ? "Всё выполнено" : "Осталось \(left) из \(s.total)"
}

// MARK: - Экран блокировки

struct LockScreenView: View {
    let state: GoalsActivityAttributes.ContentState

    var body: some View {
        let shown = Array(state.items.prefix(3))
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ProgressRingView(done: state.done, total: state.total, lineWidth: 4)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Сегодня").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    Text(state.total > shown.count
                         ? "\(headline(state)) · ещё \(state.total - shown.count) в приложении"
                         : headline(state))
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                Spacer()
                Text("\(state.done)/\(state.total)")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            ForEach(shown) { item in
                GoalRowView(item: item)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Live Activity

struct GoalsLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GoalsActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color(hex: "#F01C1C24"))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        ProgressRingView(done: s.done, total: s.total, lineWidth: 4)
                            .frame(width: 26, height: 26)
                        Text("Сегодня").font(.system(size: 16, weight: .bold))
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(s.done)/\(s.total)")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        ForEach(Array(s.items.prefix(3))) { item in
                            GoalRowView(item: item)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                }
            } compactLeading: {
                ProgressRingView(done: s.done, total: s.total, lineWidth: 3)
                    .frame(width: 18, height: 18)
            } compactTrailing: {
                Text("\(s.done)/\(s.total)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            } minimal: {
                ProgressRingView(done: s.done, total: s.total, lineWidth: 3)
                    .frame(width: 18, height: 18)
            }
            .keylineTint(Color(hex: "#FF8B5CF6"))
        }
    }
}
