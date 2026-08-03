// Ported from src/lib/format.ts. Dates are plain "YYYY-MM-DD" ISO strings;
// parsed manually (no DateFormatter/TimeZone involved) to stay
// timezone-proof, same reasoning as the web version.
import Foundation

private let monthNames = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
]

public enum DateStyle {
    case long, short
}

/// "2026-07-08" -> "July 8, 2026" (long) or "Jul 8" (short).
public func formatDate(_ iso: String?, style: DateStyle = .long) -> String {
    guard let iso else { return "" }
    let parts = iso.split(separator: "-")
    guard parts.count == 3,
          let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
          month >= 1, month <= 12 else {
        return iso
    }
    let name = monthNames[month - 1]
    switch style {
    case .long: return "\(name) \(day), \(year)"
    case .short: return "\(name.prefix(3)) \(day)"
    }
}
