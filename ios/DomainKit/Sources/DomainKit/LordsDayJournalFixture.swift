import Foundation

/// Synthetic Lord's Days for the journal's DEBUG fixture and scale tests
/// (TKL-944): one per Sunday going back from `endingOn`, preached in series
/// through books the way a pulpit does. Deterministic, so screenshots repeat.
/// The newest is always the real Revelation 2 note from the approved prototype.
public enum JournalFixture {
    public static func synthetic(count: Int, endingOn end: Date, calendar: Calendar = .current) -> [JournalEntry] {
        guard count > 0 else { return [] }
        var rng = Lcg(seed: 951)
        let weekday = calendar.component(.weekday, from: end)
        var sunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: calendar.startOfDay(for: end))!
        sunday = calendar.date(bySettingHour: 10, minute: 30, second: 0, of: sunday) ?? sunday
        var out = [real(on: sunday, calendar: calendar)]
        var series: (book: Int, chapter: Int, left: Int)?
        var used = 0
        while out.count < count {
            sunday = calendar.date(byAdding: .day, value: -7, to: sunday)!
            if rng.next() < 0.045 { continue } // away, ill, or the notebook left at home
            if series == nil || series!.left == 0 {
                let osis = pulpit[(used * 7 + Int(rng.next() * 3)) % pulpit.count]
                let book = BIBLE_BOOKS.firstIndex { $0.osis == osis }!
                used += 1
                let chapters = BIBLE_BOOKS[book].chapters
                series = (book, chapters > 20 ? 1 + Int(rng.next() * Double(chapters - 12)) : 1, min(chapters, 4 + Int(rng.next() * 10)))
            }
            let s = series!
            series = (s.book, min(s.chapter + 1, BIBLE_BOOKS[s.book].chapters), s.left - 1)
            let v1 = 1 + Int(rng.next() * 18), v2 = v1 + 3 + Int(rng.next() * 10)
            let passage = "\(BIBLE_BOOKS[s.book].name) \(s.chapter):\(v1)-\(v2)"
            var cards: [JournalCard] = []
            for _ in 0..<(3 + Int(rng.next() * 3)) { cards.append(JournalCard(kind: .keyPoint, body: points[Int(rng.next() * Double(points.count))])) }
            cards.append(JournalCard(kind: .verse, body: "", reference: verses[Int(rng.next() * Double(verses.count))]))
            cards.append(JournalCard(kind: .quote, body: quotes[Int(rng.next() * Double(quotes.count))]))
            out.append(JournalEntry(
                id: Lcg.uuid(&rng), serviceDate: sunday, passage: passage, title: titles[Int(rng.next() * Double(titles.count))],
                preacher: nil, transcript: "[Sample notes on \(passage).] " + points[Int(rng.next() * Double(points.count))],
                cards: cards, calendar: calendar
            ))
        }
        return out
    }

    private static func real(on date: Date, calendar: Calendar) -> JournalEntry {
        JournalEntry(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000951")!, serviceDate: date,
            passage: "Revelation 2:8-11", title: "To the Church at Smyrna", preacher: nil,
            transcript: "The hatred of the world is part of our heritage with Christ. Do not fear is a constant refrain in the Bible. Be faithful unto death, and I will give you the crown of life. The crown is our participation in the victory of Christ over sin, death, hell, and the Devil.",
            cards: [
                JournalCard(kind: .keyPoint, body: "The hatred of the world is part of our heritage with Christ (John 15:18-25)."),
                JournalCard(kind: .keyPoint, body: "True union with Christ is a matter of the heart, by the Spirit (Rom 2:28-29)."),
                JournalCard(kind: .keyPoint, body: "“Do not fear”: Christ walks among his lampstands; he is with us in his Church."),
                JournalCard(kind: .quote, body: "I see Christ wrestling there.", attribution: "Margaret Wilson"),
                JournalCard(kind: .verse, body: "", reference: "Revelation 2:10"),
                JournalCard(kind: .verse, body: "", reference: "Matthew 16:24"),
            ],
            calendar: calendar
        )
    }

    private static let pulpit = ["Rom", "John", "Gen", "Eph", "Gal", "Ps", "Matt", "Heb", "Exod", "Isa", "Acts", "1Cor", "Luke",
                                 "1Pet", "Dan", "Jas", "Phil", "Ruth", "Jonah", "1John", "Col", "Mark", "Rev"]
    private static let titles = ["The Golden Chain", "Thy Word Is Truth", "A Lamp unto My Feet", "Chosen before the Foundation",
                                 "In the Beginning", "He Upholds All Things", "Justified by Faith", "The Lord Is My Shepherd",
                                 "Grace upon Grace", "The Living God", "Adopted as Sons", "Kept by His Power",
                                 "The Bread of Life", "A Better Covenant", "Walk in Love", "The Means of Grace"]
    private static let points = [
        "God's purpose, not my circumstances, decides what is good.",
        "Justification is a once-for-all verdict; sanctification is a lifelong work.",
        "We are saved by grace alone, through faith alone, in Christ alone.",
        "The Lord's Day is a gift: a day of rest and of worship.",
        "Prayer is the chief exercise of faith.",
        "Christ intercedes for his people even now.",
        "Adoption gives us the Father's name and his care.",
        "The Word preached is a means of grace.",
        "Repentance is turning from sin to God, with grief and hatred of sin.",
        "Assurance grows as we use the ordinary means.",
        "The law shows us our sin and our need of a Saviour.",
        "Union with Christ is the root of every benefit.",
    ]
    private static let verses = ["Romans 8:28", "Romans 5:1", "Psalm 23:1", "John 3:16", "Ephesians 2:8", "Hebrews 4:16",
                                 "Isaiah 53:5", "Psalm 119:105", "Genesis 1:1", "Philippians 4:6", "1 Peter 1:3", "Matthew 11:28"]
    private static let quotes = [
        "Your worst day is not outside his purpose.",
        "The golden chain has no weak link, because God forged every one.",
        "A little faith is still faith in a great Christ.",
        "Grace is not a reward for the good but a gift to the guilty.",
        "We do not keep the Sabbath; it keeps us.",
    ]
}

/// A tiny seeded generator, the prototype's linear congruential one.
private struct Lcg {
    var state: UInt32
    init(seed: UInt32) { state = seed }
    mutating func next() -> Double {
        state = state &* 1_664_525 &+ 1_013_904_223
        return Double(state) / 4_294_967_296
    }
    static func uuid(_ rng: inout Lcg) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 { bytes[i] = UInt8(rng.next() * 256) }
        bytes[6] = (bytes[6] & 0x0F) | 0x40; bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
