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
        isoServiceDay(iso, calendar: calendar)
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

// MARK: Editing sermon details (TKL-1085 pass 1)

public enum SermonPassageValidation: Equatable, Sendable {
    case empty
    case valid(canonical: String, osis: String)
    case invalid(String)
}

private let sermonBookChapters: [String: Int] = Dictionary(uniqueKeysWithValues: BIBLE_BOOKS.map { ($0.osis, $0.chapters) })

private func sermonChaptersExist(_ osis: String) -> Bool {
    osis.split(separator: "-").allSatisfy { part in
        let bits = part.split(separator: ".")
        guard bits.count >= 2,
              let maxChapter = sermonBookChapters[String(bits[0])],
              let chapter = Int(bits[1]),
              chapter >= 1 && chapter <= maxChapter else {
            return false
        }
        if bits.count >= 3 {
            guard let verse = Int(bits[2]), verse >= 1 else { return false }
        }
        return true
    }
}

/// Validates a sermon passage on the same OSIS path as the server's
/// `referenceToOsis` (`src/lib/lordsDay/cards.ts`): trims whitespace, allows
/// blank (passage is optional), normalizes `Ps`/`Ps.`/`Pss` to `Psalm`, parses
/// via `citationToOsis`, and checks that every referenced chapter exists in
/// `BIBLE_BOOKS`. Never silently drops an invalid reference.
public func validateSermonPassage(_ raw: String) -> SermonPassageValidation {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return .empty }
    let errorMessage = "Enter a Bible reference like Romans 8:28 or Revelation 2:8-11."
    guard trimmed.count <= 40 else { return .invalid(errorMessage) }
    let normalized = trimmed.replacingOccurrences(
        of: #"\bPss?\b\.?"#,
        with: "Psalm",
        options: [.regularExpression, .caseInsensitive]
    )
    guard let osis = citationToOsis(normalized), sermonChaptersExist(osis) else {
        return .invalid(errorMessage)
    }
    return .valid(canonical: parseOsisBibleReference(osis), osis: osis)
}

/// Which fields of the edit sheet still match what the model read from the notes.
public struct SermonDetailsReadFlags: Equatable, Sendable {
    public let title: Bool
    public let preacher: Bool
    public let passage: Bool
    public let church: Bool
    public let serviceDate: Bool

    public static let none = SermonDetailsReadFlags(title: false, preacher: false, passage: false, church: false, serviceDate: false)

    public init(title: Bool, preacher: Bool, passage: Bool, church: Bool, serviceDate: Bool) {
        self.title = title
        self.preacher = preacher
        self.passage = passage
        self.church = church
        self.serviceDate = serviceDate
    }
}

extension SermonDetails {
    public func readFlags(
        title: String,
        preacher: String,
        passage: String,
        church: String,
        serviceDate: Date,
        calendar: Calendar = .current
    ) -> SermonDetailsReadFlags {
        func matches(_ extracted: String?, _ value: String) -> Bool {
            guard let extracted, let current = normalizedNoteField(value) else { return false }
            return extracted.caseInsensitiveCompare(current) == .orderedSame
        }
        let passageMatch: Bool = {
            guard let extracted = self.passage, let current = normalizedNoteField(passage) else { return false }
            if extracted.caseInsensitiveCompare(current) == .orderedSame { return true }
            if case .valid(let a, _) = validateSermonPassage(extracted),
               case .valid(let b, _) = validateSermonPassage(current) {
                return a == b
            }
            return false
        }()
        let dateMatch: Bool = {
            guard let extracted = self.serviceDate else { return false }
            let comps = calendar.dateComponents([.year, .month, .day], from: serviceDate)
            guard let y = comps.year, let m = comps.month, let d = comps.day else { return false }
            return String(format: "%04d-%02d-%02d", y, m, d) == extracted
        }()
        return SermonDetailsReadFlags(
            title: matches(self.title, title),
            preacher: matches(self.preacher, preacher),
            passage: passageMatch,
            church: matches(self.church, church),
            serviceDate: dateMatch
        )
    }
}

/// The five editable fields of a sermon note.
public struct SermonDetailsEdit: Equatable, Sendable {
    public var title: String?
    public var preacher: String?
    public var passage: String?
    public var church: String?
    public var serviceDate: Date

    public init(title: String?, preacher: String?, passage: String?, church: String?, serviceDate: Date) {
        self.title = title
        self.preacher = preacher
        self.passage = passage
        self.church = church
        self.serviceDate = serviceDate
    }

    @MainActor public init(note: LordsDayNote) {
        self.init(
            title: note.sermonTitle,
            preacher: note.preacher,
            passage: note.passageRef,
            church: note.church,
            serviceDate: note.serviceDate
        )
    }
}

/// A `YYYY-MM-DD` date as the notes write it, at the start of that day; nil unless it is a real date.
func isoServiceDay(_ iso: String, calendar: Calendar) -> Date? {
    let parts = iso.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3, iso.count == 10 else { return nil }
    let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
    guard let date = calendar.date(from: components),
          calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: parts[0], month: parts[1], day: parts[2])
    else { return nil }
    return date
}
