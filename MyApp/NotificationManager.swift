import Foundation
import UserNotifications

enum NotificationManager {
    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            return false
        }
    }

    static func schedule(_ routine: CareRoutine, dogName: String) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers(for: routine.id))
        guard routine.reminderLevel != .silent, routine.isActive else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(dogName) · \(routine.title)"
        content.body = routine.instructions.isEmpty ? "This care task is due." : routine.instructions
        content.sound = .default

        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = calendar.component(.hour, from: routine.timeOfDay)
        components.minute = calendar.component(.minute, from: routine.timeOfDay)

        let repeats: Bool
        switch routine.recurrence {
        case .daily:
            repeats = true
        case .weekly:
            components.weekday = calendar.component(.weekday, from: routine.startDate)
            repeats = true
        case .monthly:
            components.day = calendar.component(.day, from: routine.startDate)
            repeats = true
        case .once:
            components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: combinedDate(for: routine))
            repeats = false
        case .selectedWeekdays, .afterCompletion:
            repeats = false
        }

        if routine.recurrence == .selectedWeekdays {
            for weekday in 1...7 where routine.selectedWeekdaysMask & (1 << (weekday - 1)) != 0 {
                var weekdayComponents = components
                weekdayComponents.weekday = weekday
                let request = UNNotificationRequest(
                    identifier: "\(routine.id.uuidString)-weekday-\(weekday)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: weekdayComponents, repeats: true)
                )
                try? await center.add(request)
            }
        } else if routine.recurrence == .afterCompletion {
            // Completion-relative reminders are refreshed when a completion is recorded.
        } else {
            let request = UNNotificationRequest(
                identifier: routine.id.uuidString,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
            )
            try? await center.add(request)
        }

        if routine.reminderLevel == .important {
            let followUp = content.mutableCopy() as? UNMutableNotificationContent ?? content
            followUp.body = "Still due: \(routine.title)"
            var followUpComponents = components
            if let shiftedTime = Calendar.current.date(byAdding: .minute, value: 15, to: routine.timeOfDay) {
                followUpComponents.hour = Calendar.current.component(.hour, from: shiftedTime)
                followUpComponents.minute = Calendar.current.component(.minute, from: shiftedTime)
            }
            let request = UNNotificationRequest(
                identifier: "\(routine.id.uuidString)-followup",
                content: followUp,
                trigger: UNCalendarNotificationTrigger(dateMatching: followUpComponents, repeats: repeats)
            )
            try? await center.add(request)
        }
    }

    static func cancel(routineID: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: identifiers(for: routineID))
    }

    static func scheduleAfterCompletion(_ routine: CareRoutine, dogName: String) async {
        guard routine.recurrence == .afterCompletion,
              routine.reminderLevel != .silent,
              routine.isActive else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(dogName) · \(routine.title)"
        content.body = routine.instructions.isEmpty ? "This care task is due again." : routine.instructions
        content.sound = .default
        let interval = TimeInterval(max(1, routine.intervalDays) * 86_400)
        let request = UNNotificationRequest(
            identifier: routine.id.uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private static func identifiers(for id: UUID) -> [String] {
        [id.uuidString, "\(id.uuidString)-followup"] +
            (1...7).map { "\(id.uuidString)-weekday-\($0)" }
    }

    private static func combinedDate(for routine: CareRoutine) -> Date {
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute], from: routine.timeOfDay)
        return calendar.date(
            bySettingHour: time.hour ?? 9,
            minute: time.minute ?? 0,
            second: 0,
            of: routine.startDate
        ) ?? routine.startDate
    }
}
