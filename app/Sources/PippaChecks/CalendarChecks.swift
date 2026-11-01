import Foundation
import PippaCore

/// Reading the calendar: time range in code (week start per language, daylight saving), recognizing the question without an attachment,
/// event facts (all-day, series, multi-day, cancelled/declined, time zones, upper limit) and the separate
/// states no access / error / empty. Synthetic events via `DemoIntegrations` only, never a real calendar.
func runCalendarChecks() async {
    func calendar(_ zone: String, firstWeekday: Int, locale: String = "de_DE") -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!; c.locale = Locale(identifier: locale); c.firstWeekday = firstWeekday; c.minimumDaysInFirstWeek = 4
        return c
    }
    func at(_ c: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    let berlin = calendar("Europe/Berlin", firstWeekday: 2)
    let newYork = calendar("America/New_York", firstWeekday: 1, locale: "en_US")
    // Wednesday, 7 October 2026, 14:32 in Berlin.
    let now = at(berlin, 2026, 10, 7, 14, 32)

    // MARK: Time range

    check("Calendar: 'diese Woche' = from now to end of week, week start from the language (Mon / Sun)") {
        let de = CalendarRange.restOfWeek(now: now, calendar: berlin)
        let usNow = at(newYork, 2026, 10, 7, 14, 32)
        let us = CalendarRange.restOfWeek(now: usNow, calendar: newYork)
        return de?.start == now && de?.end == at(berlin, 2026, 10, 12) && de?.kind == .restOfWeek
            && us?.end == at(newYork, 2026, 10, 11) && us?.start == usNow
            && Locale(identifier: "de_DE").calendar.firstWeekday == 2 && Locale(identifier: "en_US").calendar.firstWeekday == 1
    }
    check("Calendar: week across the clock change (25.10.2026) ends at local midnight, 1 h longer") {
        let friday = at(berlin, 2026, 10, 23, 10)
        let rest = CalendarRange.restOfWeek(now: friday, calendar: berlin)
        let week = CalendarRange.nextWeek(now: at(berlin, 2026, 10, 14), calendar: berlin)
        let sunday = CalendarRange.day(at(berlin, 2026, 10, 25, 12), calendar: berlin)
        let spring = CalendarRange.day(at(berlin, 2026, 3, 29, 12), calendar: berlin)
        return rest?.end == at(berlin, 2026, 10, 26) && rest.map { $0.end.timeIntervalSince($0.start) } == 63 * 3600
            && week?.start == at(berlin, 2026, 10, 19) && week.map { $0.end.timeIntervalSince($0.start) } == 169 * 3600
            && sunday.map { $0.end.timeIntervalSince($0.start) } == 25 * 3600 && spring.map { $0.end.timeIntervalSince($0.start) } == 23 * 3600
    }
    check("Calendar: last weekday, weekend, next N days, upper limit 31 days") {
        let sundayNight = at(berlin, 2026, 10, 11, 22)
        let short = CalendarRange.restOfWeek(now: sundayNight, calendar: berlin)
        let weekend = CalendarRange.weekend(now: now, calendar: berlin)
        let inWeekend = CalendarRange.weekend(now: at(berlin, 2026, 10, 10, 9), calendar: berlin)
        let five = CalendarRange.nextDays(5, now: now, calendar: berlin)
        let tooLong = CalendarRange.days(from: DayDate(year: 2026, month: 10, day: 1)!, through: DayDate(year: 2026, month: 11, day: 1)!, calendar: berlin)
        let month = CalendarRange.days(from: DayDate(year: 2026, month: 10, day: 1)!, through: DayDate(year: 2026, month: 10, day: 31)!, calendar: berlin)
        return short?.end == at(berlin, 2026, 10, 12) && weekend?.start == at(berlin, 2026, 10, 10) && weekend?.end == at(berlin, 2026, 10, 12)
            && inWeekend?.start == at(berlin, 2026, 10, 10, 9) && five?.end == at(berlin, 2026, 10, 12) && five?.start == now
            && tooLong == nil && month?.end == at(berlin, 2026, 11, 1) && CalendarRange.nextDays(32, now: now, calendar: berlin) == nil
    }
    check("Calendar: the host computes tool time ranges, unknown and too long ones are rejected") {
        func resolve(_ r: CalendarToolRequest) -> CalendarRange? { CalendarRange.resolve(r, now: now, calendar: berlin) }
        return resolve(.init(period: "tomorrow"))?.start == at(berlin, 2026, 10, 8)
            && resolve(.init(period: "rest_of_week"))?.end == at(berlin, 2026, 10, 12)
            && resolve(.init(period: "dates", start: "2026-10-14"))?.end == at(berlin, 2026, 10, 15)
            && resolve(.init(period: "dates", start: "2026-10-14", end: "2026-10-16"))?.kind == .days
            && resolve(.init(period: "dates", start: "2026-10-01", end: "2026-12-01")) == nil
            && resolve(.init(period: "dates", start: "14.10.2026")) == nil && resolve(.init(period: "month")) == nil
            && resolve(.init(period: "next_days", days: 40)) == nil && resolve(.init(period: "next_days", days: 3))?.end == at(berlin, 2026, 10, 10)
    }

    // MARK: Recognizing the question (no attachment needed)

    func day(_ d: Int, month: Int = 10) -> CalendarRange? { CalendarRange.day(at(berlin, 2026, month, d), calendar: berlin) }

    // MARK: Event facts

    func event(_ id: String, _ title: String, _ start: Date, _ end: Date, allDay: Bool = false, calendar: String = "Arbeit", zone: String? = nil,
               status: CalendarEvent.Status = .confirmed, declined: Bool = false, recurring: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, title: title, start: start, end: end, allDay: allDay, calendar: calendar, timeZone: zone, status: status, declined: declined, recurring: recurring)
    }
    let week = CalendarRange.restOfWeek(now: now, calendar: berlin)!
    let fixture: [CalendarEvent] = [
        event("running", "Läuft gerade", at(berlin, 2026, 10, 7, 14), at(berlin, 2026, 10, 7, 15)),
        event("standup", "Standup", at(berlin, 2026, 10, 8, 9), at(berlin, 2026, 10, 8, 9, 30), recurring: true),
        event("standup", "Standup", at(berlin, 2026, 10, 9, 9), at(berlin, 2026, 10, 9, 9, 30), status: .cancelled, recurring: true),
        event("standup", "Standup", at(berlin, 2026, 10, 9, 9), at(berlin, 2026, 10, 9, 9, 30), status: .cancelled, recurring: true),
        event("call", "Call *NY* [x](y)", at(berlin, 2026, 10, 8, 15), at(berlin, 2026, 10, 8, 16), zone: "America/New_York", declined: true),
        event("trip", "Reise", at(berlin, 2026, 10, 9), at(berlin, 2026, 10, 10, 23, 59), allDay: true, calendar: "Privat"),
        event("party", "Feier", at(berlin, 2026, 10, 9, 20), at(berlin, 2026, 10, 10, 2), calendar: "Privat", status: .tentative),
    ]
    let fmt = DateFormatter()
    fmt.locale = berlin.locale; fmt.timeZone = berlin.timeZone; fmt.timeStyle = .short; fmt.dateStyle = .none
    let shortDay = DateFormatter()
    shortDay.locale = berlin.locale; shortDay.timeZone = berlin.timeZone; shortDay.setLocalizedDateFormatFromTemplate("EEEdMMM")
    let digest = CalendarDigest.make(CalendarFetch(events: fixture, total: fixture.count, calendars: ["Arbeit", "Privat"]), range: week, now: now, calendar: berlin)
    let entries = digest.days.flatMap { day in day.entries.map { (day.date, $0) } }
    check("Calendar: ordered by day, running event included, series per occurrence, duplicates once") {
        digest.days.map(\.date) == [DayDate(year: 2026, month: 10, day: 7)!, DayDate(year: 2026, month: 10, day: 8)!, DayDate(year: 2026, month: 10, day: 9)!]
            && entries.filter { $0.1.title == "Standup" }.count == 2 && entries.first?.1.title == "Läuft gerade"
            && entries.first?.1.time == fmt.string(from: at(berlin, 2026, 10, 7, 14)) + "–" + fmt.string(from: at(berlin, 2026, 10, 7, 15))
            && entries.contains { $0.1.title == "Standup" && $0.1.recurring && $0.0.day == 8 }
    }
    check("Calendar: all-day multi-day, across midnight, cancelled, declined, tentative, other time zone") {
        let trip = entries.first { $0.1.title == "Reise" }, party = entries.first { $0.1.title == "Feier" }
        let call = entries.first { $0.1.title.hasPrefix("Call") }, cancelled = entries.first { $0.1.title == "Standup" && $0.0.day == 9 }
        let friday = digest.days.first { $0.date.day == 9 }?.entries.map(\.title)
        let ny = DateFormatter(); ny.locale = berlin.locale; ny.timeZone = TimeZone(identifier: "America/New_York"); ny.timeStyle = .short
        return trip?.1.allDay == true && trip?.0.day == 9 && trip?.1.span?.contains(shortDay.string(from: at(berlin, 2026, 10, 10))) == true
            && friday?.first == "Reise"
            && party?.1.state == .tentative && party?.1.span?.contains(fmt.string(from: at(berlin, 2026, 10, 10, 2))) == true
            && cancelled?.1.state == .cancelled && call?.1.state == .declined
            && call?.1.otherZone?.contains("New York") == true && call?.1.otherZone?.contains(ny.string(from: at(berlin, 2026, 10, 8, 15))) == true
            && digest.activeCount == 4 && digest.inactiveCount == 2 && !digest.truncated
    }
    check("Calendar: answer concise by day, exact range and source visible, foreign titles without Markdown effect") {
        let text = digest.markdown
        return text.contains(digest.rangeLabel) && text.contains(digest.sourceLine) && digest.sourceLine.contains("Arbeit, Privat")
            && digest.rangeLabel.contains(fmt.string(from: now)) && text.contains("Call \\*NY\\* \\[x\\](y)")
            && digest.days.allSatisfy { text.contains("**" + $0.label + "**") } && !text.lowercased().contains("attach") && !text.contains("Anhang")
    }

    check("Calendar: upper limit visible (first 60 of 75), nothing silently cut off") {
        let many = (0..<75).map { i in event("e\(i)", "T\(i)", at(berlin, 2026, 10, 8, 8).addingTimeInterval(Double(i) * 600), at(berlin, 2026, 10, 8, 8).addingTimeInterval(Double(i) * 600 + 300)) }
        let demo = DemoIntegrations(granted: true)
        demo.calendarEvents = many
        let fetched = demo.eventsSync(in: week.interval, limit: CalendarReader.limit)
        let big = CalendarDigest.make(fetched, range: week, now: now, calendar: berlin)
        return big.shown == 60 && big.total == 75 && big.truncated && big.markdown.contains("60") && big.markdown.contains("75")
    }
    check("Calendar: tool data are the same facts as JSON, ISO dates with time zone") {
        guard let data = try? JSONSerialization.data(withJSONObject: digest.toolPayload()),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let range = value["range"] as? [String: Any], let days = value["days"] as? [[String: Any]],
              let first = (days.first?["events"] as? [[String: Any]])?.first else { return false }
        return range["start"] as? String == "2026-10-07T14:32" && range["end"] as? String == "2026-10-12T00:00" && range["timeZone"] as? String == "Europe/Berlin"
            && days.count == 3 && first["title"] as? String == "Läuft gerade" && value["count"] as? Int == 4 && value["truncated"] as? Bool == false
            && (days[1]["events"] as? [[String: Any]])?.contains { ($0["title"] as? String)?.hasPrefix("Call *NY*") == true && $0["state"] as? String == "declined" } == true
    }

    // MARK: Access, error, empty

    await checkAsync("Calendar: no access, denied, error and empty stay separate; without access nothing is read") {
        let fresh = DemoIntegrations()
        let needs = await CalendarReader.read(week, from: fresh, now: now, calendar: berlin)
        let denied = DemoIntegrations(); denied.set(.calendar, .denied)
        let refused = await CalendarReader.read(week, from: denied, now: now, calendar: berlin)
        let odd = DemoIntegrations(); odd.set(.calendar, .unavailable("Gerade nicht."))
        let unavailable = await CalendarReader.read(week, from: odd, now: now, calendar: berlin)
        let broken = DemoIntegrations(granted: true); broken.calendarFails = true
        let failed = await CalendarReader.read(week, from: broken, now: now, calendar: berlin)
        let empty = DemoIntegrations(granted: true); empty.calendarEvents = []
        let nothing = await CalendarReader.read(week, from: empty, now: now, calendar: berlin)
        let none = DemoIntegrations(granted: true); none.calendarEvents = []; none.calendarNames = []
        let noCalendars = await CalendarReader.read(week, from: none, now: now, calendar: berlin)
        guard case .read(let emptyDigest) = nothing, case .read(let noneDigest) = noCalendars, case .failed(let why) = failed else { return false }
        let emptyText = L("Nothing in your calendar for this period.", table: "Calendar")
        return needs == .needsAccess && refused == .denied && unavailable == .failed("Gerade nicht.")
            && fresh.calendarReads.isEmpty && denied.calendarReads.isEmpty
            && why == CalendarReadResult.failureText && !why.contains(emptyText) && broken.calendarReads.count == 1
            && emptyDigest.days.isEmpty && emptyDigest.markdown.contains(emptyText) && emptyDigest.markdown.contains(emptyDigest.sourceLine)
            && !noneDigest.markdown.contains(emptyText) && noneDigest.markdown.contains(L("I didn’t find a calendar on this Mac that I can read.", table: "Calendar"))
    }
    await checkAsync("Calendar: permission only on request, then read directly; tool replies per state") {
        let demo = DemoIntegrations()
        demo.calendarEvents = fixture
        let before = await CalendarReader.toolReply(.init(period: "rest_of_week"), from: demo, now: now, calendar: berlin)
        let invalid = await CalendarReader.toolReply(.init(period: "dates", start: "2026-01-01", end: "2026-12-31"), from: demo, now: now, calendar: berlin)
        guard before.status == .needsAccess, before.payload == nil, invalid.status == .invalidRange, demo.calendarReads.isEmpty else { return false }
        guard await demo.requestAccess(.calendar) == .granted else { return false }
        let after = await CalendarReader.toolReply(.init(period: "rest_of_week"), from: demo, now: now, calendar: berlin)
        let value = after.payload.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        return after.status == .ok && value?["count"] as? Int == 4 && demo.calendarReads.count == 1
    }

    // MARK: Conversation

}

/// ConversationStore lives on the MainActor.
@MainActor func runCalendarStoreChecks() {
}

extension DemoIntegrations {
    /// For checks without `await` in the synchronous `check`.
    func eventsSync(in interval: DateInterval, limit: Int) -> CalendarFetch {
        let box = LockedBox(CalendarFetch(events: [], total: 0, calendars: []))
        let done = DispatchSemaphore(value: 0)
        Task.detached { if let value = try? await self.events(in: interval, limit: limit) { box.mutate { $0 = value } }; done.signal() }
        done.wait()
        return box.value
    }
}
