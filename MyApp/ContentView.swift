import SwiftData
import SwiftUI

struct ContentView: View {
    @Query(sort: \Dog.createdAt) private var dogs: [Dog]
    @State private var selectedTab = 0
    @State private var showingAddDog = false
    @State private var hasCheckedOnboarding = false

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "checklist") }
                .tag(0)

            CareCalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(1)

            RoutinesView()
                .tabItem { Label("Routines", systemImage: "repeat") }
                .tag(2)

            SuppliesView()
                .tabItem { Label("Supplies", systemImage: "shippingbox.fill") }
                .tag(3)

            DogsView()
                .tabItem { Label("Dogs", systemImage: "pawprint.fill") }
                .tag(4)
        }
        .tint(.orange)
        .onAppear {
            guard !hasCheckedOnboarding else { return }
            hasCheckedOnboarding = true
            showingAddDog = dogs.isEmpty
        }
        .sheet(isPresented: $showingAddDog) {
            DogEditorView(isOnboarding: true)
                .interactiveDismissDisabled(dogs.isEmpty)
        }
    }
}

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color.orange.opacity(0.12), Color.clear],
            startPoint: .topLeading,
            endPoint: .center
        )
        .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Dog.self, CareRoutine.self, CareCompletion.self, FoodPlan.self, FoodDelivery.self], inMemory: true)
}
