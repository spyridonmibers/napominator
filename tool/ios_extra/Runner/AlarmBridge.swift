import AVFoundation
import Flutter
import Foundation
import SwiftUI
#if canImport(AlarmKit)
import ActivityKit
import AlarmKit
#endif

/// Канал napominator/alarm на iPhone: настоящие будильники через AlarmKit (iOS 26+).
/// На более старых iOS будильники не ставятся — Dart показывает предупреждение.
class AlarmBridge: NSObject {
    static let shared = AlarmBridge()
    private static let storedIdsKey = "napominator.alarmkit.ids"
    private var previewPlayer: AVAudioPlayerHolder?

    func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "napominator/alarm", binaryMessenger: registrar.messenger())
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isSupported":
            result(Self.supported)
        case "missingPermissions":
            missingPermissions(result: result)
        case "requestPermission":
            requestAuthorization { _ in result(true) }
        case "sync":
            sync(json: call.arguments as? String ?? "[]", result: result)
        case "preview":
            previewPlayer = AVAudioPlayerHolder(sound: call.arguments as? String)
            result(true)
        case "stopPreview":
            previewPlayer?.stop()
            previewPlayer = nil
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    static var supported: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    private func missingPermissions(result: @escaping FlutterResult) {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            switch AlarmManager.shared.authorizationState {
            case .authorized:
                result([String]())
            default:
                result(["authorization"])
            }
            return
        }
        #endif
        result([String]())
    }

    private func requestAuthorization(_ done: @escaping (Bool) -> Void) {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            Task {
                let state = try? await AlarmManager.shared.requestAuthorization()
                await MainActor.run { done(state == .authorized) }
            }
            return
        }
        #endif
        done(false)
    }

    private func sync(json: String, result: @escaping FlutterResult) {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let data = json.data(using: .utf8) ?? Data()
            let alarms = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
            Task {
                let ok = await AlarmKitScheduler.sync(alarms: alarms, storedIdsKey: Self.storedIdsKey)
                await MainActor.run { result(ok) }
            }
            return
        }
        #endif
        result(false)
    }
}

/// Прослушивание мелодии из бандла.
final class AVAudioPlayerHolder {
    private var player: AVAudioPlayer?

    init(sound: String?) {
        guard let sound = sound, sound.hasPrefix("builtin:") else { return }
        let key = String(sound.dropFirst("builtin:".count))
        guard let url = Bundle.main.url(forResource: "alarm_\(key)", withExtension: "caf") else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    func stop() {
        player?.stop()
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct NapAlarmMetadata: AlarmMetadata {
    var label: String
}

@available(iOS 26.0, *)
enum AlarmKitScheduler {
    /// Сколько будущих срабатываний ставить для графиков «через день» и «N/M».
    static let fixedAhead = 14

    static func sync(alarms: [[String: Any]], storedIdsKey: String) async -> Bool {
        let manager = AlarmManager.shared
        if manager.authorizationState == .notDetermined {
            _ = try? await manager.requestAuthorization()
        }
        guard manager.authorizationState == .authorized else { return false }

        // Снимаем всё, что ставили раньше
        let defaults = UserDefaults.standard
        for raw in defaults.stringArray(forKey: storedIdsKey) ?? [] {
            if let id = UUID(uuidString: raw) {
                try? manager.cancel(id: id)
            }
        }

        var newIds: [String] = []
        for a in alarms {
            guard (a["enabled"] as? Bool) ?? true else { continue }
            let minutes = (a["minutes"] as? Int) ?? 420
            let label = ((a["label"] as? String) ?? "").isEmpty ? "Будильник" : (a["label"] as! String)
            let sound = (a["sound"] as? String) ?? "builtin:soft"
            for schedule in schedules(for: a, minutes: minutes) {
                let id = UUID()
                if await place(id: id, schedule: schedule, label: label, sound: sound) {
                    newIds.append(id.uuidString)
                }
            }
        }
        defaults.set(newIds, forKey: storedIdsKey)
        return true
    }

    private static func schedules(for a: [String: Any], minutes: Int) -> [Alarm.Schedule] {
        let repeatType = (a["repeat"] as? String) ?? "daily"
        let time = Alarm.Schedule.Relative.Time(hour: minutes / 60, minute: minutes % 60)
        let all: [Locale.Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
        switch repeatType {
        case "daily":
            return [.relative(.init(time: time, repeats: .weekly(all)))]
        case "weekdays":
            let days = ((a["weekdays"] as? [Int]) ?? []).compactMap { d -> Locale.Weekday? in
                (1...7).contains(d) ? all[d - 1] : nil
            }
            return days.isEmpty ? [] : [.relative(.init(time: time, repeats: .weekly(days)))]
        default:
            // «Через день» и свой график — ставим конкретные даты на ближайшие дни.
            return fixedDates(for: a, minutes: minutes).map { .fixed($0) }
        }
    }

    private static func fixedDates(for a: [String: Any], minutes: Int) -> [Date] {
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        let start = fmt.date(from: (a["startDate"] as? String) ?? "") ?? cal.startOfDay(for: Date())
        let repeatType = (a["repeat"] as? String) ?? "everyOtherDay"
        let on = max(1, (a["cycleOn"] as? Int) ?? 2)
        let off = max(0, (a["cycleOff"] as? Int) ?? 2)
        let now = Date()
        var res: [Date] = []
        var day = cal.startOfDay(for: now)
        for _ in 0..<400 {
            if res.count >= fixedAhead { break }
            let diff = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: day).day ?? 0
            let rings: Bool
            if diff < 0 {
                rings = false
            } else if repeatType == "everyOtherDay" {
                rings = diff % 2 == 0
            } else {
                rings = diff % (on + off) < on
            }
            if rings, let at = cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day), at > now {
                res.append(at)
            }
            day = cal.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)
        }
        return res
    }

    private static func place(id: UUID, schedule: Alarm.Schedule, label: String, sound: String) async -> Bool {
        let stop = AlarmButton(text: "Выключить", textColor: .white, systemImageName: "stop.circle.fill")
        let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: label), stopButton: stop)
        let attributes = AlarmAttributes<NapAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: NapAlarmMetadata(label: label),
            tintColor: Color(red: 0.39, green: 0.40, blue: 0.95)
        )
        let alertSound: AlertConfiguration.AlertSound
        if sound.hasPrefix("builtin:") {
            alertSound = .named("alarm_\(sound.dropFirst("builtin:".count)).caf")
        } else {
            alertSound = .default
        }
        let configuration = AlarmManager.AlarmConfiguration<NapAlarmMetadata>(
            countdownDuration: nil,
            schedule: schedule,
            attributes: attributes,
            stopIntent: nil,
            secondaryIntent: nil,
            sound: alertSound
        )
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            return true
        } catch {
            return false
        }
    }
}
#endif
