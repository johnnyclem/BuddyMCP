import Foundation
import EventKit
import OSLog

class CalendarManager: ObservableObject {
    static let shared = CalendarManager()
    
    private let eventStore = EKEventStore()
    private let logger = Logger(subsystem: "com.mcp.agent", category: "CalendarManager")
    
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var calendars: [EKCalendar] = []
    @Published var isAuthorized = false
    
    private init() {
        updateAuthorizationStatus()
        loadCalendars()
    }
    
    private func updateAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        isAuthorized = authorizationStatus == .authorized
    }
    
    func requestAccess() async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            eventStore.requestAccess(to: .event) { granted, error in
                Task { @MainActor in
                    self.updateAuthorizationStatus()
                    if let error = error {
                        self.logger.error("Calendar access denied: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    } else {
                        self.logger.info("Calendar access granted: \(granted)")
                        self.loadCalendars()
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }
    
    private func loadCalendars() {
        DispatchQueue.main.async {
            self.calendars = self.eventStore.calendars(for: .event)
                .filter { $0.allowsContentModifications }
                .sorted { $0.title < $1.title }
        }
    }
    
    func createEvent(title: String, startDate: Date, location: String? = nil, duration: TimeInterval = 3600, calendar: EKCalendar? = nil) async throws -> [String: Any] {
        if !isAuthorized {
            let granted = try await requestAccess()
            guard granted else { throw CalendarError.accessDenied }
        }
        
        // Use specified calendar or the first available one
        let targetCalendar = calendar ?? calendars.first
        guard let calendar = targetCalendar else {
            throw CalendarError.noCalendarsAvailable
        }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(duration)
        event.calendar = calendar
        
        if let location = location {
            event.location = location
        }
        
        // Add alarms
        let alarm = EKAlarm(relativeOffset: -15 * 60) // 15 minutes before
        event.addAlarm(alarm)
        
        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            logger.info("Created calendar event: \(title)")
            
            return [
                "success": true,
                "event_id": event.eventIdentifier,
                "title": event.title,
                "start_date": ISO8601DateFormatter().string(from: event.startDate),
                "end_date": ISO8601DateFormatter().string(from: event.endDate),
                "location": event.location ?? "",
                "calendar": calendar.title
            ]
        } catch {
            logger.error("Failed to create event: \(error.localizedDescription)")
            throw CalendarError.creationFailed(error)
        }
    }
    
    func findEvents(title: String? = nil, dateRange: DateInterval? = nil, calendar: EKCalendar? = nil) async throws -> [[String: Any]] {
        if !isAuthorized {
            let granted = try await requestAccess()
            guard granted else { throw CalendarError.accessDenied }
        }
        
        let predicate: NSPredicate?
        
        if let dateRange = dateRange {
            predicate = eventStore.predicateForEvents(withStart: dateRange.start, end: dateRange.end, calendars: calendar.map { [$0] })
        } else {
            let now = Date()
            let weekLater = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: now)!
            predicate = eventStore.predicateForEvents(withStart: now, end: weekLater, calendars: calendar.map { [$0] })
        }
        
        guard let predicate = predicate else {
            throw CalendarError.invalidPredicate
        }
        
        let events = eventStore.events(matching: predicate)
        let filteredEvents = events.filter { event in
            if let title = title, !event.title.localizedCaseInsensitiveContains(title) {
                return false
            }
            return true
        }
        
        return filteredEvents.map { event in
            [
                "title": event.title,
                "start_date": ISO8601DateFormatter().string(from: event.startDate),
                "end_date": ISO8601DateFormatter().string(from: event.endDate),
                "location": event.location ?? "",
                "event_id": event.eventIdentifier,
                "calendar": event.calendar.title,
                "notes": event.notes ?? ""
            ]
        }
    }
    
    func updateEvent(eventId: String, updates: [String: Any]) async throws -> [String: Any] {
        if !isAuthorized {
            let granted = try await requestAccess()
            guard granted else { throw CalendarError.accessDenied }
        }
        
        guard let event = eventStore.event(withIdentifier: eventId) else {
            throw CalendarError.eventNotFound
        }
        
        if let title = updates["title"] as? String {
            event.title = title
        }
        
        if let startDateString = updates["start_date"] as? String,
           let startDate = ISO8601DateFormatter().date(from: startDateString) {
            event.startDate = startDate
        }
        
        if let endDateString = updates["end_date"] as? String,
           let endDate = ISO8601DateFormatter().date(from: endDateString) {
            event.endDate = endDate
        }
        
        if let location = updates["location"] as? String {
            event.location = location
        }
        
        if let notes = updates["notes"] as? String {
            event.notes = notes
        }
        
        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            logger.info("Updated calendar event: \(event.title)")
            
            return [
                "success": true,
                "event_id": event.eventIdentifier,
                "title": event.title,
                "start_date": ISO8601DateFormatter().string(from: event.startDate),
                "end_date": ISO8601DateFormatter().string(from: event.endDate),
                "location": event.location ?? ""
            ]
        } catch {
            logger.error("Failed to update event: \(error.localizedDescription)")
            throw CalendarError.updateFailed(error)
        }
    }
    
    func deleteEvent(eventId: String) async throws -> [String: Any] {
        if !isAuthorized {
            let granted = try await requestAccess()
            guard granted else { throw CalendarError.accessDenied }
        }
        
        guard let event = eventStore.event(withIdentifier: eventId) else {
            throw CalendarError.eventNotFound
        }
        
        do {
            try eventStore.remove(event, span: .thisEvent, commit: true)
            logger.info("Deleted calendar event: \(event.title)")
            
            return [
                "success": true,
                "event_id": eventId,
                "message": "Event deleted successfully"
            ]
        } catch {
            logger.error("Failed to delete event: \(error.localizedDescription)")
            throw CalendarError.deletionFailed(error)
        }
    }
    
    func createReminder(title: String, dueDate: Date? = nil, priority: Int = 0) async throws -> [String: Any] {
        // Note: Reminders require additional entitlements and setup
        // This is a placeholder implementation
        
        if !isAuthorized {
            let granted = try await requestAccess()
            guard granted else { throw CalendarError.accessDenied }
        }
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        
        if let dueDate = dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        }
        
        reminder.priority = priority
        
        do {
            try eventStore.save(reminder, commit: true)
            logger.info("Created reminder: \(title)")
            
            return [
                "success": true,
                "reminder_id": reminder.calendarItemIdentifier,
                "title": reminder.title,
                "due_date": dueDate != nil ? ISO8601DateFormatter().string(from: dueDate!) : "",
                "priority": priority
            ]
        } catch {
            logger.error("Failed to create reminder: \(error.localizedDescription)")
            throw CalendarError.reminderCreationFailed(error)
        }
    }
    
    func findAvailableSlots(duration: TimeInterval, startDate: Date, endDate: Date) async throws -> [[String: Any]] {
        if !isAuthorized {
            let granted = try await requestAccess()
            guard granted else { throw CalendarError.accessDenied }
        }
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        
        var availableSlots: [[String: Any]] = []
        var currentStart = startDate
        
        for event in events {
            if event.startDate.timeIntervalSince(currentStart) >= duration {
                availableSlots.append([
                    "start": ISO8601DateFormatter().string(from: currentStart),
                    "end": ISO8601DateFormatter().string(from: event.startDate)
                ])
            }
            currentStart = max(currentStart, event.endDate)
        }
        
        // Check after the last event
        if endDate.timeIntervalSince(currentStart) >= duration {
            availableSlots.append([
                "start": ISO8601DateFormatter().string(from: currentStart),
                "end": ISO8601DateFormatter().string(from: endDate)
            ])
        }
        
        return availableSlots
    }
}

// MARK: - Calendar Errors
enum CalendarError: Error, LocalizedError {
    case accessDenied
    case noCalendarsAvailable
    case creationFailed(Error)
    case updateFailed(Error)
    case deletionFailed(Error)
    case reminderCreationFailed(Error)
    case eventNotFound
    case invalidPredicate
    
    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access denied"
        case .noCalendarsAvailable:
            return "No calendars available for writing"
        case .creationFailed(let error):
            return "Failed to create event: \(error.localizedDescription)"
        case .updateFailed(let error):
            return "Failed to update event: \(error.localizedDescription)"
        case .deletionFailed(let error):
            return "Failed to delete event: \(error.localizedDescription)"
        case .reminderCreationFailed(let error):
            return "Failed to create reminder: \(error.localizedDescription)"
        case .eventNotFound:
            return "Event not found"
        case .invalidPredicate:
            return "Invalid calendar predicate"
        }
    }
}
