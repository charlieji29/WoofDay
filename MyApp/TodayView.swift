import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Dog.createdAt) private var dogs: [Dog]
    @Query private var routines: [CareRoutine]
    @Query private var completions: [CareCompletion]
    @Query private var foodPlans: [FoodPlan]
    @State private var selectedDogID: UUID?
    @State private var duplicateRoutine: CareRoutine?

    private var filteredRoutines: [CareRoutine] {
        guard let selectedDogID else { return routines }
        return routines.filter { $0.dogID == selectedDogID }
    }

    private var occurrences: [CareOccurrence] {
        ScheduleEngine.occurrences(on: .now, routines: filteredRoutines, completions: completions)
    }

    private var pending: [CareOccurrence] {
        occurrences.filter { $0.completion == nil }
    }

    private var completed: [CareOccurrence] {
        occurrences.filter { $0.completion != nil }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        greeting
                        if dogs.count > 1 { dogFilter }

                        if dogs.isEmpty {
                            ContentUnavailableView(
                                "Add your first dog",
                                systemImage: "pawprint",
                                description: Text("Create a dog profile to begin planning care.")
                            )
                            .padding(.top, 60)
                        } else if occurrences.isEmpty {
                            ContentUnavailableView(
                                "A clear day",
                                systemImage: "sun.max.fill",
                                description: Text("No care is scheduled for today.")
                            )
                            .padding(.top, 60)
                        } else {
                            occurrenceSection("Overdue", items: pending.filter { $0.dueDate < .now }, color: .red)
                            occurrenceSection("Next", items: pending.filter { $0.dueDate >= .now }, color: .orange)
                            occurrenceSection("Completed", items: completed, color: .green)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("PawPlan")
            .alert("Possible duplicate dose", isPresented: Binding(
                get: { duplicateRoutine != nil },
                set: { if !$0 { duplicateRoutine = nil } }
            )) {
                Button("Cancel", role: .cancel) { duplicateRoutine = nil }
                Button("Record anyway") {
                    if let duplicateRoutine,
                       let occurrence = occurrences.first(where: { $0.routine.id == duplicateRoutine.id }) {
                        record(occurrence)
                    }
                    duplicateRoutine = nil
                }
            } message: {
                Text("A dose of \(duplicateRoutine?.title ?? "this medication") has already been recorded today.")
            }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(pending.isEmpty ? "All cared for" : "\(pending.count) thing\(pending.count == 1 ? "" : "s") left today")
                .font(.largeTitle.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dogFilter: some View {
        ScrollView(.horizontal) {
            HStack {
                filterChip(title: "All dogs", id: nil)
                ForEach(dogs) { dog in
                    filterChip(title: "\(dog.symbol) \(dog.name)", id: dog.id)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func filterChip(title: String, id: UUID?) -> some View {
        Button(title) { selectedDogID = id }
            .buttonStyle(.borderedProminent)
            .tint(selectedDogID == id ? .orange : Color(.tertiarySystemFill))
            .foregroundStyle(selectedDogID == id ? .white : .primary)
    }

    @ViewBuilder
    private func occurrenceSection(_ title: String, items: [CareOccurrence], color: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(color)
                ForEach(items) { occurrence in
                    CareOccurrenceCard(
                        occurrence: occurrence,
                        dogName: dogName(for: occurrence.routine.dogID),
                        foodDetail: foodDetail(for: occurrence.routine),
                        onComplete: { attemptCompletion(occurrence) },
                        onUndo: { undo(occurrence) }
                    )
                }
            }
        }
    }

    private func dogName(for id: UUID) -> String {
        dogs.first(where: { $0.id == id })?.name ?? "Dog"
    }

    private func foodDetail(for routine: CareRoutine) -> String? {
        guard let foodPlanID = routine.foodPlanID,
              let plan = foodPlans.first(where: { $0.id == foodPlanID }) else { return nil }
        return "\(plan.recipe.isEmpty ? plan.provider : plan.recipe) · \(routine.inventoryDeduction.formatted()) \(plan.unitLabel)"
    }

    private func attemptCompletion(_ occurrence: CareOccurrence) {
        if occurrence.routine.category == .prescription {
            let alreadyRecorded = completions.contains {
                $0.routineID == occurrence.routine.id &&
                Calendar.current.isDateInToday($0.completedAt)
            }
            if alreadyRecorded {
                duplicateRoutine = occurrence.routine
                return
            }
        }
        record(occurrence)
    }

    private func record(_ occurrence: CareOccurrence) {
        let completion = CareCompletion(
            routineID: occurrence.routine.id,
            dogID: occurrence.routine.dogID,
            scheduledDate: occurrence.dueDate,
            status: .completed,
            quantity: occurrence.routine.inventoryDeduction > 0 ? occurrence.routine.inventoryDeduction : nil
        )
        modelContext.insert(completion)

        if let foodPlanID = occurrence.routine.foodPlanID,
           let plan = foodPlans.first(where: { $0.id == foodPlanID }) {
            plan.currentUnits = max(0, plan.currentUnits - occurrence.routine.inventoryDeduction)
        }
        if let remaining = occurrence.routine.remainingQuantity {
            occurrence.routine.remainingQuantity = max(0, remaining - max(1, occurrence.routine.inventoryDeduction))
        }
        try? modelContext.save()
        if occurrence.routine.recurrence == .afterCompletion {
            Task {
                await NotificationManager.scheduleAfterCompletion(
                    occurrence.routine,
                    dogName: dogName(for: occurrence.routine.dogID)
                )
            }
        }
    }

    private func undo(_ occurrence: CareOccurrence) {
        guard let completion = occurrence.completion else { return }
        if let foodPlanID = occurrence.routine.foodPlanID,
           let plan = foodPlans.first(where: { $0.id == foodPlanID }) {
            plan.currentUnits += completion.quantity ?? occurrence.routine.inventoryDeduction
        }
        if let remaining = occurrence.routine.remainingQuantity {
            occurrence.routine.remainingQuantity = remaining + max(1, completion.quantity ?? occurrence.routine.inventoryDeduction)
        }
        modelContext.delete(completion)
        try? modelContext.save()
    }
}

private struct CareOccurrenceCard: View {
    let occurrence: CareOccurrence
    let dogName: String
    let foodDetail: String?
    let onComplete: () -> Void
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(occurrence.routine.category.color.opacity(0.16))
                    .frame(width: 44, height: 44)
                Image(systemName: occurrence.routine.category.symbol)
                    .foregroundStyle(occurrence.routine.category.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(occurrence.routine.title)
                    .font(.headline)
                Text("\(dogName) · \(occurrence.dueDate.formatted(date: .omitted, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let foodDetail {
                    Text(foodDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !occurrence.routine.dosage.isEmpty {
                    Text(occurrence.routine.dosage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            if occurrence.completion != nil {
                Button(action: onUndo) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
                .accessibilityLabel("Undo \(occurrence.routine.title)")
            } else {
                Button(action: onComplete) {
                    Image(systemName: "circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Complete \(occurrence.routine.title)")
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
