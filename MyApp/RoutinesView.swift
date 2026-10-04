import SwiftData
import SwiftUI

struct RoutinesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Dog.createdAt) private var dogs: [Dog]
    @Query private var routines: [CareRoutine]
    @State private var editingRoutine: CareRoutine?
    @State private var showingNewRoutine = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                List {
                    ForEach(dogs) { dog in
                        Section("\(dog.symbol) \(dog.name)") {
                            ForEach(routines.filter { $0.dogID == dog.id }) { routine in
                                Button {
                                    editingRoutine = routine
                                } label: {
                                    RoutineRow(routine: routine)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .leading) {
                                    Button(routine.isActive ? "Pause" : "Resume") {
                                        routine.isActive.toggle()
                                        if routine.isActive {
                                            Task { await NotificationManager.schedule(routine, dogName: dog.name) }
                                        } else {
                                            NotificationManager.cancel(routineID: routine.id)
                                        }
                                    }
                                    .tint(.orange)
                                }
                                .swipeActions {
                                    Button("Delete", role: .destructive) {
                                        NotificationManager.cancel(routineID: routine.id)
                                        modelContext.delete(routine)
                                    }
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .overlay {
                    if routines.isEmpty {
                        ContentUnavailableView(
                            "No routines yet",
                            systemImage: "repeat",
                            description: Text("Add feeding, medication, grooming, or any custom care.")
                        )
                    }
                }
            }
            .navigationTitle("Routines")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add routine", systemImage: "plus") {
                        showingNewRoutine = true
                    }
                    .disabled(dogs.isEmpty)
                }
            }
            .sheet(isPresented: $showingNewRoutine) {
                RoutineEditorView(routine: nil)
            }
            .sheet(item: $editingRoutine) { routine in
                RoutineEditorView(routine: routine)
            }
        }
    }
}

private struct RoutineRow: View {
    let routine: CareRoutine

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: routine.category.symbol)
                .foregroundStyle(routine.category.color)
                .frame(width: 32, height: 32)
                .background(routine.category.color.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(routine.title)
                    .foregroundStyle(.primary)
                Text("\(routine.recurrence.title) · \(routine.timeOfDay.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !routine.isActive {
                Text("Paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct RoutineEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Dog.createdAt) private var dogs: [Dog]
    @Query private var foodPlans: [FoodPlan]

    let routine: CareRoutine?
    @State private var dogID: UUID?
    @State private var title = ""
    @State private var category = CareCategory.feeding
    @State private var instructions = ""
    @State private var startDate = Date.now
    @State private var hasEndDate = false
    @State private var endDate = Date.now
    @State private var timeOfDay = Date.now
    @State private var recurrence = RecurrenceKind.daily
    @State private var weekdaysMask = 0b1111111
    @State private var intervalDays = 1
    @State private var reminder = ReminderLevel.normal
    @State private var dosage = ""
    @State private var tracksRemaining = false
    @State private var remainingQuantity = 0.0
    @State private var inventoryDeduction = 0.0
    @State private var foodPlanID: UUID?
    @State private var notificationsAllowed = true

    private let weekdaySymbols = Calendar.current.veryShortWeekdaySymbols

    init(routine: CareRoutine?) {
        self.routine = routine
        _dogID = State(initialValue: routine?.dogID)
        _title = State(initialValue: routine?.title ?? "")
        _category = State(initialValue: routine?.category ?? .feeding)
        _instructions = State(initialValue: routine?.instructions ?? "")
        _startDate = State(initialValue: routine?.startDate ?? .now)
        _hasEndDate = State(initialValue: routine?.endDate != nil)
        _endDate = State(initialValue: routine?.endDate ?? .now)
        _timeOfDay = State(initialValue: routine?.timeOfDay ?? .now)
        _recurrence = State(initialValue: routine?.recurrence ?? .daily)
        _weekdaysMask = State(initialValue: routine?.selectedWeekdaysMask ?? 0b1111111)
        _intervalDays = State(initialValue: routine?.intervalDays ?? 1)
        _reminder = State(initialValue: routine?.reminderLevel ?? .normal)
        _dosage = State(initialValue: routine?.dosage ?? "")
        _tracksRemaining = State(initialValue: routine?.remainingQuantity != nil)
        _remainingQuantity = State(initialValue: routine?.remainingQuantity ?? 0)
        _inventoryDeduction = State(initialValue: routine?.inventoryDeduction ?? 0)
        _foodPlanID = State(initialValue: routine?.foodPlanID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Care") {
                    Picker("Dog", selection: $dogID) {
                        Text("Choose a dog").tag(UUID?.none)
                        ForEach(dogs) { dog in
                            Text("\(dog.symbol) \(dog.name)").tag(Optional(dog.id))
                        }
                    }
                    TextField("Routine name", text: $title)
                    Picker("Category", selection: $category) {
                        ForEach(CareCategory.allCases) { item in
                            Label(item.title, systemImage: item.symbol).tag(item)
                        }
                    }
                    TextField("Instructions", text: $instructions, axis: .vertical)
                }

                Section("Schedule") {
                    DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                    DatePicker("Time", selection: $timeOfDay, displayedComponents: .hourAndMinute)
                    Picker("Repeats", selection: $recurrence) {
                        ForEach(RecurrenceKind.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    if recurrence == .selectedWeekdays {
                        HStack {
                            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                                Button(symbol) {
                                    weekdaysMask ^= 1 << index
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(weekdaysMask & (1 << index) != 0 ? .orange : .gray.opacity(0.25))
                            }
                        }
                    }
                    if recurrence == .afterCompletion {
                        Stepper("Every \(intervalDays) day\(intervalDays == 1 ? "" : "s")", value: $intervalDays, in: 1...365)
                    }
                    Toggle("End date", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                }

                Section("Reminder") {
                    Picker("Level", selection: $reminder) {
                        ForEach(ReminderLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    if !notificationsAllowed && reminder != .silent {
                        Label("Notifications are disabled. The routine will still appear in PawPlan.", systemImage: "bell.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if category == .prescription || category == .supplement {
                    Section("Medication") {
                        TextField("Dosage and instructions", text: $dosage)
                        Toggle("Track remaining doses", isOn: $tracksRemaining)
                        if tracksRemaining {
                            TextField("Remaining doses", value: $remainingQuantity, format: .number)
                            TextField("Used per completion", value: $inventoryDeduction, format: .number)
                        }
                    }
                }

                if category == .feeding {
                    Section("Food inventory") {
                        Picker("Food plan", selection: $foodPlanID) {
                            Text("Do not track inventory").tag(UUID?.none)
                            ForEach(foodPlans.filter { $0.dogID == dogID }) { plan in
                                Text("\(plan.provider) · \(plan.recipe)").tag(Optional(plan.id))
                            }
                        }
                        if foodPlanID != nil {
                            TextField("Units per feeding", value: $inventoryDeduction, format: .number)
                        }
                    }
                }
            }
            .navigationTitle(routine == nil ? "New Routine" : "Edit Routine")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || dogID == nil)
                }
            }
            .onAppear {
                if dogID == nil { dogID = dogs.first?.id }
            }
        }
    }

    private func save() {
        guard let dogID, let dog = dogs.first(where: { $0.id == dogID }) else { return }
        let value = routine ?? CareRoutine(
            dogID: dogID,
            title: title,
            category: category,
            startDate: startDate,
            timeOfDay: timeOfDay,
            recurrence: recurrence,
            reminderLevel: reminder
        )
        value.dogID = dogID
        value.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.category = category
        value.instructions = instructions
        value.startDate = startDate
        value.endDate = hasEndDate ? endDate : nil
        value.timeOfDay = timeOfDay
        value.recurrence = recurrence
        value.selectedWeekdaysMask = weekdaysMask
        value.intervalDays = intervalDays
        value.reminderLevel = reminder
        value.dosage = dosage
        value.remainingQuantity = tracksRemaining ? remainingQuantity : nil
        value.inventoryDeduction = inventoryDeduction
        value.foodPlanID = category == .feeding ? foodPlanID : nil
        if routine == nil { modelContext.insert(value) }
        try? modelContext.save()

        Task {
            if reminder != .silent {
                notificationsAllowed = await NotificationManager.requestAuthorization()
            }
            await NotificationManager.schedule(value, dogName: dog.name)
            dismiss()
        }
    }
}
