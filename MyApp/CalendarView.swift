import SwiftData
import SwiftUI

struct CareCalendarView: View {
    @Query private var routines: [CareRoutine]
    @Query private var completions: [CareCompletion]
    @Query(sort: \Dog.createdAt) private var dogs: [Dog]
    @State private var selectedDate = Date.now

    private var days: [Date] {
        (0..<14).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: .now) }
    }

    private var occurrences: [CareOccurrence] {
        ScheduleEngine.occurrences(on: selectedDate, routines: routines, completions: completions)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                VStack(spacing: 16) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(days, id: \.self) { day in
                                Button {
                                    selectedDate = day
                                } label: {
                                    VStack(spacing: 6) {
                                        Text(day.formatted(.dateTime.weekday(.abbreviated)))
                                            .font(.caption)
                                        Text(day.formatted(.dateTime.day()))
                                            .font(.title3.bold())
                                    }
                                    .frame(width: 48, height: 60)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Calendar.current.isDate(day, inSameDayAs: selectedDate) ? .orange : Color(.tertiarySystemFill))
                                .foregroundStyle(Calendar.current.isDate(day, inSameDayAs: selectedDate) ? .white : .primary)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .scrollIndicators(.hidden)

                    List(occurrences) { occurrence in
                        HStack(spacing: 12) {
                            Image(systemName: occurrence.routine.category.symbol)
                                .foregroundStyle(occurrence.routine.category.color)
                                .frame(width: 28)
                            VStack(alignment: .leading) {
                                Text(occurrence.routine.title)
                                Text("\(dogName(for: occurrence.routine.dogID)) · \(occurrence.dueDate.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if occurrence.completion != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .listRowBackground(Color.gray.opacity(0.08))
                    }
                    .scrollContentBackground(.hidden)
                    .overlay {
                        if occurrences.isEmpty {
                            ContentUnavailableView("Nothing scheduled", systemImage: "calendar.badge.checkmark")
                        }
                    }
                }
            }
            .navigationTitle("Calendar")
        }
    }

    private func dogName(for id: UUID) -> String {
        dogs.first(where: { $0.id == id })?.name ?? "Dog"
    }
}
