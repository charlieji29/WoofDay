import SwiftData
import SwiftUI

struct SuppliesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Dog.createdAt) private var dogs: [Dog]
    @Query private var plans: [FoodPlan]
    @Query private var deliveries: [FoodDelivery]
    @State private var editingPlan: FoodPlan?
    @State private var showingNewPlan = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(plans) { plan in
                            supplyCard(plan)
                        }
                    }
                    .padding()
                }
                .overlay {
                    if plans.isEmpty {
                        ContentUnavailableView(
                            "No supplies tracked",
                            systemImage: "shippingbox",
                            description: Text("Add a food plan to forecast inventory and deliveries.")
                        )
                    }
                }
            }
            .navigationTitle("Supplies")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add food plan", systemImage: "plus") {
                        showingNewPlan = true
                    }
                    .disabled(dogs.isEmpty)
                }
            }
            .sheet(isPresented: $showingNewPlan) {
                FoodPlanEditorView(plan: nil)
            }
            .sheet(item: $editingPlan) { plan in
                FoodPlanEditorView(plan: plan)
            }
        }
    }

    private func supplyCard(_ plan: FoodPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.provider)
                        .font(.title3.bold())
                    Text([dogName(for: plan.dogID), plan.recipe].filter { !$0.isEmpty }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Edit") { editingPlan = plan }
                    .buttonStyle(.bordered)
            }

            HStack {
                metric(title: "On hand", value: "\(plan.currentUnits.formatted()) \(plan.unitLabel)")
                Divider()
                metric(title: "Runs out", value: plan.runOutDate?.formatted(date: .abbreviated, time: .omitted) ?? "Not enough data")
            }

            if let delivery = plan.nextDeliveryDate {
                let shortfall = plan.runOutDate.map { Calendar.current.startOfDay(for: $0) < Calendar.current.startOfDay(for: delivery) } ?? false
                Label(
                    "Next delivery \(delivery.formatted(date: .abbreviated, time: .omitted))",
                    systemImage: shortfall ? "exclamationmark.triangle.fill" : "truck.box.fill"
                )
                .foregroundStyle(shortfall ? .red : .green)

                if shortfall {
                    Text("Food may run out before this delivery arrives.")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                Button("Mark shipment received") {
                    receiveShipment(plan)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }

            if let url = URL(string: plan.retailerURLString), !plan.retailerURLString.isEmpty {
                Link("Open provider website", destination: url)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .contextMenu {
            Button("Delete", role: .destructive) {
                modelContext.delete(plan)
            }
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func receiveShipment(_ plan: FoodPlan) {
        guard let expectedDate = plan.nextDeliveryDate else { return }
        let delivery = FoodDelivery(foodPlanID: plan.id, expectedDate: expectedDate, quantity: plan.deliveryQuantity)
        delivery.isReceived = true
        delivery.receivedAt = .now
        modelContext.insert(delivery)
        plan.currentUnits += plan.deliveryQuantity
        plan.nextDeliveryDate = Calendar.current.date(byAdding: .day, value: plan.deliveryIntervalDays, to: expectedDate)
        try? modelContext.save()
    }

    private func dogName(for id: UUID) -> String {
        dogs.first(where: { $0.id == id })?.name ?? "Dog"
    }
}

struct FoodPlanEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Dog.createdAt) private var dogs: [Dog]

    let plan: FoodPlan?
    @State private var dogID: UUID?
    @State private var provider = ""
    @State private var recipe = ""
    @State private var unitLabel = "packs"
    @State private var currentUnits = 0.0
    @State private var unitsPerDay = 1.0
    @State private var hasDelivery = true
    @State private var nextDelivery = Date.now
    @State private var deliveryQuantity = 14.0
    @State private var deliveryIntervalDays = 14
    @State private var retailerURL = ""
    @State private var notes = ""

    init(plan: FoodPlan?) {
        self.plan = plan
        _dogID = State(initialValue: plan?.dogID)
        _provider = State(initialValue: plan?.provider ?? "")
        _recipe = State(initialValue: plan?.recipe ?? "")
        _unitLabel = State(initialValue: plan?.unitLabel ?? "packs")
        _currentUnits = State(initialValue: plan?.currentUnits ?? 0)
        _unitsPerDay = State(initialValue: plan?.unitsPerDay ?? 1)
        _hasDelivery = State(initialValue: plan?.nextDeliveryDate != nil)
        _nextDelivery = State(initialValue: plan?.nextDeliveryDate ?? .now)
        _deliveryQuantity = State(initialValue: plan?.deliveryQuantity ?? 14)
        _deliveryIntervalDays = State(initialValue: plan?.deliveryIntervalDays ?? 14)
        _retailerURL = State(initialValue: plan?.retailerURLString ?? "")
        _notes = State(initialValue: plan?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Food plan") {
                    Picker("Dog", selection: $dogID) {
                        Text("Choose a dog").tag(UUID?.none)
                        ForEach(dogs) { dog in
                            Text("\(dog.symbol) \(dog.name)").tag(Optional(dog.id))
                        }
                    }
                    TextField("Provider", text: $provider)
                    TextField("Recipe", text: $recipe)
                    TextField("Unit name", text: $unitLabel)
                }

                Section("Inventory") {
                    TextField("Units on hand", value: $currentUnits, format: .number)
                    TextField("Units used per day", value: $unitsPerDay, format: .number)
                }

                Section("Delivery") {
                    Toggle("Track delivery", isOn: $hasDelivery)
                    if hasDelivery {
                        DatePicker("Next delivery", selection: $nextDelivery, displayedComponents: .date)
                        TextField("Units arriving", value: $deliveryQuantity, format: .number)
                        Stepper("Every \(deliveryIntervalDays) days", value: $deliveryIntervalDays, in: 1...90)
                    }
                    TextField("Provider website", text: $retailerURL)
                }

                Section("Notes") {
                    TextField("Storage or feeding notes", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle(plan == nil ? "New Food Plan" : "Edit Food Plan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(provider.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || dogID == nil)
                }
            }
            .onAppear {
                if dogID == nil { dogID = dogs.first?.id }
            }
        }
    }

    private func save() {
        guard let dogID else { return }
        let value = plan ?? FoodPlan(dogID: dogID, provider: provider)
        value.dogID = dogID
        value.provider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        value.recipe = recipe
        value.unitLabel = unitLabel.isEmpty ? "units" : unitLabel
        value.currentUnits = max(0, currentUnits)
        value.unitsPerDay = max(0, unitsPerDay)
        value.nextDeliveryDate = hasDelivery ? nextDelivery : nil
        value.deliveryQuantity = max(0, deliveryQuantity)
        value.deliveryIntervalDays = deliveryIntervalDays
        value.retailerURLString = retailerURL
        value.notes = notes
        if plan == nil { modelContext.insert(value) }
        try? modelContext.save()
        dismiss()
    }
}
