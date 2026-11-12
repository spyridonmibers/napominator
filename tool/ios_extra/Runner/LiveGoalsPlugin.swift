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
        let appChannel = FlutterMethodChannel(name: "napominator/app", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: appChannel)
        AlarmBridge.shared.register(with: registrar)
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
        if call.method == "setIcon" {
            setIcon(call.arguments as? String ?? "indigo", result: result)
            return
        }
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

extension LiveGoalsPlugin {
    /// Сменить иконку: indigo — основная, остальные — AppIcon-<Name> из Assets.
    func setIcon(_ key: String, result: @escaping FlutterResult) {
        let names = [
            "sunset": "AppIcon-Sunset",
            "mint": "AppIcon-Mint",
            "ocean": "AppIcon-Ocean",
            "graphite": "AppIcon-Graphite",
        ]
        DispatchQueue.main.async {
            guard UIApplication.shared.supportsAlternateIcons else {
                result(false)
                return
            }
            UIApplication.shared.setAlternateIconName(names[key]) { error in
                result(error == nil)
            }
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
