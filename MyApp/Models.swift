import Foundation
import SwiftData
import SwiftUI

enum CareCategory: String, CaseIterable, Codable, Identifiable {
    case prescription, supplement, feeding, water, walk, bathing, brushing, dental, nails, prevention, appointment, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prescription: "Prescription"
        case .supplement: "Supplement"
        case .feeding: "Feeding"
        case .water: "Fresh water"
        case .walk: "Walk"
        case .bathing: "Bathing"
        case .brushing: "Brushing"
        case .dental: "Dental care"
        case .nails: "Nail trim"
        case .prevention: "Prevention"
        case .appointment: "Appointment"
        case .custom: "Custom"
        }
    }

    var symbol: String {
        switch self {
        case .prescription: "pills.fill"
        case .supplement: "cross.case.fill"
        case .feeding: "fork.knife"
        case .water: "drop.fill"
        case .walk: "figure.walk"
        case .bathing: "shower.fill"
        case .brushing: "comb.fill"
        case .dental: "mouth.fill"
        case .nails: "scissors"
        case .prevention: "shield.fill"
        case .appointment: "calendar"
        case .custom: "pawprint.fill"
        }
    }

    var color: Color {
        switch self {
        case .prescription, .prevention: .orange
        case .supplement, .appointment: .purple
        case .feeding: .green
        case .water, .bathing: .blue
        case .walk: .mint
        case .brushing, .dental, .nails: .pink
        case .custom: .brown
        }
    }
}

enum RecurrenceKind: String, CaseIterable, Codable, Identifiable {
    case once, daily, selectedWeekdays, weekly, monthly, afterCompletion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .once: "Once"
        case .daily: "Every day"
        case .selectedWeekdays: "Selected weekdays"
        case .weekly: "Every week"
        case .monthly: "Every month"
        case .afterCompletion: "After completion"
        }
    }
}

enum ReminderLevel: String, CaseIterable, Codable, Identifiable {
    case silent, normal, important

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum CompletionStatus: String, Codable {
    case completed, skipped
}

@Model
final class Dog {
    @Attribute(.unique) var id: UUID
    var name: String
    var breed: String
    var birthDate: Date?
    var symbol: String
    var createdAt: Date

    init(name: String, breed: String = "", birthDate: Date? = nil, symbol: String = "🐶") {
        id = UUID()
        self.name = name
        self.breed = breed
        self.birthDate = birthDate
        self.symbol = symbol
        createdAt = .now
    }
}

@Model
final class CareRoutine {
    @Attribute(.unique) var id: UUID
    var dogID: UUID
    var title: String
    var categoryRaw: String
    var instructions: String
    var startDate: Date
    var endDate: Date?
    var timeOfDay: Date
    var recurrenceRaw: String
    var selectedWeekdaysMask: Int
    var intervalDays: Int
    var reminderRaw: String
    var dosage: String
    var remainingQuantity: Double?
    var inventoryDeduction: Double
    var foodPlanID: UUID?
    var isActive: Bool

    var category: CareCategory {
        get { CareCategory(rawValue: categoryRaw) ?? .custom }
        set { categoryRaw = newValue.rawValue }
    }

    var recurrence: RecurrenceKind {
        get { RecurrenceKind(rawValue: recurrenceRaw) ?? .daily }
        set { recurrenceRaw = newValue.rawValue }
    }

    var reminderLevel: ReminderLevel {
        get { ReminderLevel(rawValue: reminderRaw) ?? .normal }
        set { reminderRaw = newValue.rawValue }
    }

    init(
        dogID: UUID,
        title: String,
        category: CareCategory,
        startDate: Date = .now,
        timeOfDay: Date = .now,
        recurrence: RecurrenceKind = .daily,
        reminderLevel: ReminderLevel = .normal
    ) {
        id = UUID()
        self.dogID = dogID
        self.title = title
        categoryRaw = category.rawValue
        instructions = ""
        self.startDate = startDate
        self.timeOfDay = timeOfDay
        recurrenceRaw = recurrence.rawValue
        selectedWeekdaysMask = 0b1111111
        intervalDays = 1
        reminderRaw = reminderLevel.rawValue
        dosage = ""
        inventoryDeduction = 0
        isActive = true
    }
}

@Model
final class CareCompletion {
    @Attribute(.unique) var id: UUID
    var routineID: UUID
    var dogID: UUID
    var scheduledDate: Date
    var completedAt: Date
    var statusRaw: String
    var quantity: Double?
    var notes: String
    var caregiverName: String

    var status: CompletionStatus {
        CompletionStatus(rawValue: statusRaw) ?? .completed
    }

    init(
        routineID: UUID,
        dogID: UUID,
        scheduledDate: Date,
        status: CompletionStatus,
        quantity: Double? = nil,
        notes: String = "",
        caregiverName: String = "Me"
    ) {
        id = UUID()
        self.routineID = routineID
        self.dogID = dogID
        self.scheduledDate = scheduledDate
        completedAt = .now
        statusRaw = status.rawValue
        self.quantity = quantity
        self.notes = notes
        self.caregiverName = caregiverName
    }
}

@Model
final class FoodPlan {
    @Attribute(.unique) var id: UUID
    var dogID: UUID
    var provider: String
    var recipe: String
    var unitLabel: String
    var currentUnits: Double
    var unitsPerDay: Double
    var nextDeliveryDate: Date?
    var deliveryQuantity: Double
    var deliveryIntervalDays: Int
    var retailerURLString: String
    var notes: String

    init(dogID: UUID, provider: String, recipe: String = "") {
        id = UUID()
        self.dogID = dogID
        self.provider = provider
        self.recipe = recipe
        unitLabel = "packs"
        currentUnits = 0
        unitsPerDay = 1
        deliveryQuantity = 0
        deliveryIntervalDays = 14
        retailerURLString = ""
        notes = ""
    }

    var runOutDate: Date? {
        guard unitsPerDay > 0, currentUnits > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: Int(floor(currentUnits / unitsPerDay)), to: .now)
    }
}

@Model
final class FoodDelivery {
    @Attribute(.unique) var id: UUID
    var foodPlanID: UUID
    var expectedDate: Date
    var quantity: Double
    var isReceived: Bool
    var receivedAt: Date?

    init(foodPlanID: UUID, expectedDate: Date, quantity: Double) {
        id = UUID()
        self.foodPlanID = foodPlanID
        self.expectedDate = expectedDate
        self.quantity = quantity
        isReceived = false
    }
}

struct CareOccurrence: Identifiable {
    let routine: CareRoutine
    let dueDate: Date
    let completion: CareCompletion?

    var id: String {
        "\(routine.id.uuidString)-\(dueDate.timeIntervalSinceReferenceDate)"
    }
}

enum ScheduleEngine {
    static func occurrences(
        on day: Date,
        routines: [CareRoutine],
        completions: [CareCompletion],
        calendar: Calendar = .current
    ) -> [CareOccurrence] {
        routines.compactMap { routine in
            guard isScheduled(routine, on: day, completions: completions, calendar: calendar),
                  let dueDate = calendar.date(
                    bySettingHour: calendar.component(.hour, from: routine.timeOfDay),
                    minute: calendar.component(.minute, from: routine.timeOfDay),
                    second: 0,
                    of: day
                  ) else { return nil }

            let completion = completions.first {
                $0.routineID == routine.id && calendar.isDate($0.scheduledDate, inSameDayAs: dueDate)
            }
            return CareOccurrence(routine: routine, dueDate: dueDate, completion: completion)
        }
        .sorted { $0.dueDate < $1.dueDate }
    }

    static func isScheduled(
        _ routine: CareRoutine,
        on day: Date,
        completions: [CareCompletion],
        calendar: Calendar = .current
    ) -> Bool {
        guard routine.isActive,
              day >= calendar.startOfDay(for: routine.startDate),
              routine.endDate.map({ day <= calendar.endOfDay(for: $0) }) ?? true else { return false }

        switch routine.recurrence {
        case .once:
            return calendar.isDate(day, inSameDayAs: routine.startDate)
        case .daily:
            return true
        case .selectedWeekdays:
            let weekday = calendar.component(.weekday, from: day) - 1
            return routine.selectedWeekdaysMask & (1 << weekday) != 0
        case .weekly:
            return calendar.component(.weekday, from: day) == calendar.component(.weekday, from: routine.startDate)
        case .monthly:
            return calendar.component(.day, from: day) == calendar.component(.day, from: routine.startDate)
        case .afterCompletion:
            let last = completions
                .filter { $0.routineID == routine.id && $0.status == .completed }
                .max { $0.completedAt < $1.completedAt }
            let anchor = last?.completedAt ?? routine.startDate
            let next = calendar.date(byAdding: .day, value: max(1, routine.intervalDays), to: calendar.startOfDay(for: anchor))
            return next.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        }
    }
}

private extension Calendar {
    func endOfDay(for date: Date) -> Date {
        self.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay(for: date)) ?? date
    }
}
