import Foundation

// Which sermon a Lord's Day was (TKL-1061). The cards call reads the title,
// preacher, passage, church and date from the notes when they say them
// (`sermon` in src/lib/lordsDay/handler.ts; each field null otherwise, never
// invented). Drafting fills the note's empty fields with them, and every place
// that named a Lord's Day by its date alone names the sermon instead.

/// The sermon as the notes state it. A blank string reads as missing.
public struct SermonDetails: Codable, Equatable, Sendable {
    public let title: String?
    public let preacher: String?
    /// A canonical reference ("Revelation 2:8-11").
    public let passage: String?
    public let church: String?
    /// `YYYY-MM-DD`, as written on the page.
    public let serviceDate: String?

    public init(title: String?, preacher: String?, passage: String?, church: String?, serviceDate: String?) {
        self.title = normalizedNoteField(title)
        self.preacher = normalizedNoteField(preacher)
        self.passage = normalizedNoteField(passage)
        self.church = normalizedNoteField(church)
        self.serviceDate = normalizedNoteField(serviceDate)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            title: try c.decodeIfPresent(String.self, forKey: .title),
            preacher: try c.decodeIfPresent(String.self, forKey: .preacher),
            passage: try c.decodeIfPresent(String.self, forKey: .passage),
            church: try c.decodeIfPresent(String.self, forKey: .church),
            serviceDate: try c.decodeIfPresent(String.self, forKey: .serviceDate)
        )
    }

    public var isEmpty: Bool { [title, preacher, passage, church, serviceDate].allSatisfy { $0 == nil } }

    /// Each field from `self` if it has one, otherwise from `other`.
    func filling(from other: SermonDetails) -> SermonDetails {
        SermonDetails(title: title ?? other.title, preacher: preacher ?? other.preacher, passage: passage ?? other.passage,
                      church: church ?? other.church, serviceDate: serviceDate ?? other.serviceDate)
    }
}

/// The Sunday on or before `date`: the service date a new note starts with.
public func lastSunday(onOrBefore date: Date, calendar: Calendar = .current) -> Date {
    let day = calendar.startOfDay(for: date)
    let back = (calendar.component(.weekday, from: day) - 1 + 7) % 7 // weekday 1 = Sunday
    return calendar.date(byAdding: .day, value: -back, to: day) ?? day
}

extension LordsDayNote {
    /// Fills the fields the person left empty from what the notes say; returns whether
    /// anything changed (and then marks the note updated, so it syncs like any edit).
    /// A date read from the page replaces the service date only while it is still the
    /// default a new note starts with, and only when it is plausible: within a year
    /// before the note was made and not after it (a misread year must not move the week).
    @discardableResult
    public func fill(with details: SermonDetails, calendar: Calendar = .current) -> Bool {
        var changed = false
        func fill(_ field: ReferenceWritableKeyPath<LordsDayNote, String?>, _ value: String?) {
            guard let value, normalizedNoteField(self[keyPath: field]) == nil else { return }
            self[keyPath: field] = value
            changed = true
        }
        fill(\.sermonTitle, details.title)
        fill(\.preacher, details.preacher)
        fill(\.passageRef, details.passage)
        fill(\.church, details.church)
        if let raw = details.serviceDate, let date = Self.day(raw, calendar: calendar),
           calendar.isDate(serviceDate, inSameDayAs: lastSunday(onOrBefore: createdAt, calendar: calendar)),
           !calendar.isDate(serviceDate, inSameDayAs: date) {
            let made = calendar.startOfDay(for: createdAt)
            if let earliest = calendar.date(byAdding: .day, value: -366, to: made), date >= earliest, date <= made {
                serviceDate = date
                changed = true
            }
        }
        if changed { updatedAt = max(Date(), updatedAt.addingTimeInterval(0.001)) }
        return changed
    }

    private static func day(_ iso: String, calendar: Calendar) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, iso.count == 10 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: parts[0], month: parts[1], day: parts[2])
        else { return nil }
        return date
    }
}

/// How a Lord's Day is named: its title, else its passage, else its date, with the
/// preacher and the passage (when it isn't already the headline) beneath.
public struct SermonHeading: Equatable, Sendable {
    public let headline: String
    public let byline: String?
    /// False when the headline is only the date (a Lord's Day kept before TKL-1061, or notes that named nothing).
    public let hasSermonName: Bool

    public init(title: String?, passage: String?, preacher: String?, date: String) {
        let title = normalizedNoteField(title), passage = normalizedNoteField(passage), preacher = normalizedNoteField(preacher)
        headline = title ?? passage ?? date
        hasSermonName = title != nil || passage != nil
        let beneath = [preacher, title == nil ? nil : passage].compactMap { $0 }
        byline = beneath.isEmpty ? nil : beneath.joined(separator: " · ")
    }

    @MainActor public init(note: LordsDayNote, date: String) {
        self.init(title: note.sermonTitle, passage: note.passageRef, preacher: note.preacher, date: date)
    }
}
