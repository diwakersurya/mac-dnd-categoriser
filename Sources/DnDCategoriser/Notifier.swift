import Foundation
import UserNotifications

/// UNUserNotificationCenter crashes when the process is not inside an app bundle (e.g. `swift run`).
/// Everything here is a no-op that logs in that case.
enum Notifier {
    private static var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    static func requestPermission() {
        guard isBundled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    static func moveFailed(_ names: [String]) {
        guard isBundled else {
            NSLog("DnDCategoriser: some files were not moved: \(names)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = names.count == 1 ? "1 file was not moved" : "\(names.count) files were not moved"
        content.body = names.joined(separator: ", ")
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
