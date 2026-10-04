import SwiftData
import SwiftUI

@main
struct PawPlanApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            Dog.self,
            CareRoutine.self,
            CareCompletion.self,
            FoodPlan.self,
            FoodDelivery.self
        ])
    }
}
