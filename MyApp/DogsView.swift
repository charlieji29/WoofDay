import SwiftData
import SwiftUI

struct DogsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Dog.createdAt) private var dogs: [Dog]
    @Query private var routines: [CareRoutine]
    @Query private var completions: [CareCompletion]
    @Query private var foodPlans: [FoodPlan]
    @Query private var deliveries: [FoodDelivery]
    @State private var editingDog: Dog?
    @State private var showingNewDog = false
    @State private var dogToDelete: Dog?

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                List {
                    ForEach(dogs) { dog in
                        NavigationLink {
                            DogDetailView(dog: dog)
                        } label: {
                            HStack(spacing: 14) {
                                Text(dog.symbol)
                                    .font(.largeTitle)
                                    .frame(width: 54, height: 54)
                                    .background(Color.orange.opacity(0.12), in: Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(dog.name)
                                        .font(.headline)
                                    Text(dog.breed.isEmpty ? "Dog" : dog.breed)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Edit") { editingDog = dog }
                                .tint(.orange)
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) { dogToDelete = dog }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .overlay {
                    if dogs.isEmpty {
                        ContentUnavailableView("No dogs yet", systemImage: "pawprint")
                    }
                }
            }
            .navigationTitle("Dogs")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add dog", systemImage: "plus") { showingNewDog = true }
                }
            }
            .sheet(isPresented: $showingNewDog) {
                DogEditorView(isOnboarding: false)
            }
            .sheet(item: $editingDog) { dog in
                DogEditorView(dog: dog)
            }
            .confirmationDialog(
                "Delete \(dogToDelete?.name ?? "dog")?",
                isPresented: Binding(
                    get: { dogToDelete != nil },
                    set: { if !$0 { dogToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete dog and care data", role: .destructive) {
                    if let dogToDelete { delete(dogToDelete) }
                }
                Button("Cancel", role: .cancel) { dogToDelete = nil }
            } message: {
                Text("This permanently removes the dog’s routines, history, and food plans.")
            }
        }
    }

    private func delete(_ dog: Dog) {
        let removedPlanIDs = Set(foodPlans.filter { $0.dogID == dog.id }.map(\.id))
        routines.filter { $0.dogID == dog.id }.forEach {
            NotificationManager.cancel(routineID: $0.id)
            modelContext.delete($0)
        }
        completions.filter { $0.dogID == dog.id }.forEach(modelContext.delete)
        deliveries.filter { removedPlanIDs.contains($0.foodPlanID) }.forEach(modelContext.delete)
        foodPlans.filter { $0.dogID == dog.id }.forEach(modelContext.delete)
        modelContext.delete(dog)
        try? modelContext.save()
        dogToDelete = nil
    }
}

struct DogDetailView: View {
    let dog: Dog
    @Query private var completions: [CareCompletion]
    @Query private var routines: [CareRoutine]

    private var history: [CareCompletion] {
        completions
            .filter { $0.dogID == dog.id }
            .sorted { $0.completedAt > $1.completedAt }
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Text(dog.symbol)
                        .font(.system(size: 72))
                    Text(dog.name)
                        .font(.largeTitle.bold())
                    if !dog.breed.isEmpty {
                        Text(dog.breed)
                            .foregroundStyle(.secondary)
                    }
                    if let birthDate = dog.birthDate {
                        Text("Born \(birthDate.formatted(date: .long, time: .omitted))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }

            Section("Care history") {
                if history.isEmpty {
                    Text("Completed care will appear here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(history) { completion in
                    HStack {
                        Image(systemName: completion.status == .completed ? "checkmark.circle.fill" : "forward.fill")
                            .foregroundStyle(completion.status == .completed ? .green : .secondary)
                        VStack(alignment: .leading) {
                            Text(routineName(for: completion.routineID))
                            Text(completion.completedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(completion.caregiverName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(dog.name)
    }

    private func routineName(for id: UUID) -> String {
        routines.first(where: { $0.id == id })?.title ?? "Deleted routine"
    }
}

struct DogEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let dog: Dog?
    let isOnboarding: Bool
    @State private var name: String
    @State private var breed: String
    @State private var symbol: String
    @State private var hasBirthDate: Bool
    @State private var birthDate: Date

    init(dog: Dog? = nil, isOnboarding: Bool = false) {
        self.dog = dog
        self.isOnboarding = isOnboarding
        _name = State(initialValue: dog?.name ?? "")
        _breed = State(initialValue: dog?.breed ?? "")
        _symbol = State(initialValue: dog?.symbol ?? "🐶")
        _hasBirthDate = State(initialValue: dog?.birthDate != nil)
        _birthDate = State(initialValue: dog?.birthDate ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                if isOnboarding {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Welcome to PawPlan")
                                .font(.largeTitle.bold())
                            Text("Start with the dog whose day you want to make easier.")
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.clear)
                    }
                }

                Section("Profile") {
                    TextField("Dog’s name", text: $name)
                    TextField("Breed (optional)", text: $breed)
                    Picker("Icon", selection: $symbol) {
                        ForEach(["🐶", "🐕", "🦮", "🐕‍🦺", "🐩"], id: \.self) { icon in
                            Text(icon).tag(icon)
                        }
                    }
                    Toggle("Add birthday", isOn: $hasBirthDate)
                    if hasBirthDate {
                        DatePicker("Birthday", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle(dog == nil ? "Add Dog" : "Edit Dog")
            .toolbar {
                if !isOnboarding {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isOnboarding ? "Get Started" : "Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let value = dog ?? Dog(name: name)
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.breed = breed.trimmingCharacters(in: .whitespacesAndNewlines)
        value.symbol = symbol
        value.birthDate = hasBirthDate ? birthDate : nil
        if dog == nil { modelContext.insert(value) }
        try? modelContext.save()
        dismiss()
    }
}
