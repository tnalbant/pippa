import PippaCore

/// Dates in an answer against what the turn read (the Stadtwerke letter from the acceptance runs).
func runDateEvidenceChecks() {
    let letter = """
    Musterstadt, 20. Oktober 2026
    Bitte überweisen Sie den Betrag bis zum 15. November 2026. Einwände können Sie innerhalb von vier Wochen nach Zugang erheben.
    """
    let today = DayDate(year: 2026, month: 11, day: 1)!
    func read(_ text: String = letter) -> DateEvidence {
        var e = DateEvidence()
        e.toolStarted(id: "r", isWrite: false, arguments: "{}")
        e.toolEnded(id: "r", done: true, result: text)
        return e
    }

    check("Dates: a worked-out objection date is named, quoted dates in another form are not") {
        read().unsupported(in: "Zahlen bis 15.11.2026 (Brief vom 2026-10-20). Einwände bis 19. November 2026.", today: today) == ["19. November 2026"]
    }
    check("Dates: English answers, each day once") {
        read().unsupported(in: "Pay by November 15, 2026. Object by 17th November 2026, i.e. Nov 17 2026.", today: today) == ["17th November 2026"]
    }
    check("Dates: within a week of today passes (a weekday turned into a date)") {
        read().unsupported(in: "Eingetragen für Dienstag, 03.11.2026.", today: today).isEmpty
    }
    check("Dates: nothing read, nothing checked; a failed read is no source") {
        var failed = DateEvidence()
        failed.toolStarted(id: "x", isWrite: false, arguments: "")
        failed.toolEnded(id: "x", done: false, result: letter)
        return DateEvidence().unsupported(in: "Weihnachten ist am 25.12.2026.", today: today).isEmpty
            && !failed.hasSources
    }
    check("Dates: the person's own words and a confirmed write's arguments count, an unconfirmed write's do not") {
        var e = read()
        e.add(prompt: "Trag mir den 30.11.2026 ein.")
        e.toolStarted(id: "w1", isWrite: true, arguments: #"{"date":"2026-12-04"}"#)
        e.toolEnded(id: "w1", done: true, result: #"{"done":true}"#)
        e.toolStarted(id: "w2", isWrite: true, arguments: #"{"date":"2026-12-09"}"#)
        e.toolEnded(id: "w2", done: false, result: #"{"done":false}"#)
        return e.unsupported(in: "30.11.2026, 04.12.2026 und 09.12.2026", today: today) == ["09.12.2026"]
    }
}
