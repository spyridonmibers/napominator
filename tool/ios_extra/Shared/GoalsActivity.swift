import Foundation
import ActivityKit
import AppIntents

/// Одна цель в Live Activity.
struct GoalItem: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var done: Bool
    var color: String
}

/// Live Activity «Цели на сегодня» (Dynamic Island + экран блокировки).
@available(iOS 16.1, *)
struct GoalsActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var items: [GoalItem]
        var done: Int
        var total: Int
    }

    var name: String
}

/// Кнопка-кружок в Live Activity (iOS 17+). Выполняется в процессе приложения:
/// записывает отметку в очередь, которую Dart применит при следующем запуске/возврате.
@available(iOS 17.0, *)
struct ToggleGoalIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Отметить цель"

    @Parameter(title: "Цель")
    var goalId: String

    init() {}

    init(goalId: String) {
        self.goalId = goalId
    }

    func perform() async throws -> some IntentResult {
        let key = "flutter.pending_toggles"
        let defaults = UserDefaults.standard
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        var list: [[String: String]] = []
        if let raw = defaults.string(forKey: key),
           let data = raw.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            list = arr
        }
        list.append(["id": goalId, "date": today])
        if let out = try? JSONSerialization.data(withJSONObject: list),
           let str = String(data: out, encoding: .utf8) {
            defaults.set(str, forKey: key)
        }

        for activity in Activity<GoalsActivityAttributes>.activities {
            var state = activity.content.state
            if let i = state.items.firstIndex(where: { $0.id == goalId }) {
                state.items[i].done.toggle()
                state.done += state.items[i].done ? 1 : -1
                state.done = max(0, min(state.done, state.total))
                await activity.update(ActivityContent(state: state, staleDate: activity.content.staleDate))
            }
        }

        await MainActor.run {
            NotificationCenter.default.post(name: Notification.Name("NapominatorPendingToggle"), object: nil)
        }
        return .result()
    }
}
