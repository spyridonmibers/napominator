import ActivityKit
import Flutter
import UIKit

/// Канал napominator/live: Dart присылает состояние, здесь запускаем/обновляем Live Activity.
class LiveGoalsPlugin: NSObject, FlutterPlugin {
    private static var observer: NSObjectProtocol?

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "napominator/live", binaryMessenger: registrar.messenger())
        let instance = LiveGoalsPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        if let old = observer {
            NotificationCenter.default.removeObserver(old)
        }
        observer = NotificationCenter.default.addObserver(
            forName: Notification.Name("NapominatorPendingToggle"),
            object: nil,
            queue: .main
        ) { _ in
            channel.invokeMethod("pendingChanged", arguments: nil)
        }
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "update", let json = call.arguments as? String else {
            result(FlutterMethodNotImplemented)
            return
        }
        if #available(iOS 16.2, *) {
            LiveGoals.update(json: json) { ok in result(ok) }
        } else {
            result(false)
        }
    }
}

@available(iOS 16.2, *)
enum LiveGoals {
    static func update(json: String, completion: @escaping (Bool) -> Void) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let data = json.data(using: .utf8),
              let state = try? JSONDecoder().decode(GoalsActivityAttributes.ContentState.self, from: data)
        else {
            completion(false)
            return
        }
        Task { @MainActor in
            let all = Activity<GoalsActivityAttributes>.activities
            if state.total == 0 {
                for activity in all {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                completion(true)
                return
            }
            let startOfDay = Calendar.current.startOfDay(for: Date())
            let stale = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)
            let content = ActivityContent(state: state, staleDate: stale)
            let active = all.filter { $0.activityState == .active }
            if let current = active.first {
                await current.update(content)
                for extra in active.dropFirst() {
                    await extra.end(nil, dismissalPolicy: .immediate)
                }
                completion(true)
            } else {
                for old in all {
                    await old.end(nil, dismissalPolicy: .immediate)
                }
                do {
                    _ = try Activity.request(
                        attributes: GoalsActivityAttributes(name: "today"),
                        content: content,
                        pushType: nil
                    )
                    completion(true)
                } catch {
                    completion(false)
                }
            }
        }
    }
}
