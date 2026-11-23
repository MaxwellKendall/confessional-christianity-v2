import Foundation

/// Checks a name typed into the Add a child sheet (TKL-941). The sheet shows
/// `message` inline under the field instead of an alert.
public enum ChildName {
    public static let maxLength = 40

    public enum Check: Equatable, Sendable {
        case valid(String)
        case empty
        case tooLong
        /// The name matches an existing child's, ignoring case; carries theirs.
        case duplicate(existing: String)

        public static let duplicate = Check.duplicate(existing: "")

        /// The inline error, or nil when there is nothing to say yet.
        public var message: String? {
            switch self {
            case .valid, .empty: nil
            case .tooLong: "Keep it to \(ChildName.maxLength) letters or fewer."
            case .duplicate(let name): "\(name) is already on this iPhone. Use a different name."
            }
        }

        public static func == (lhs: Check, rhs: Check) -> Bool {
            switch (lhs, rhs) {
            case let (.valid(a), .valid(b)): a == b
            case (.empty, .empty), (.tooLong, .tooLong), (.duplicate, .duplicate): true
            default: false
            }
        }
    }

    public static func validate(_ raw: String, existing: [String]) -> Check {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return .empty }
        if name.count > maxLength { return .tooLong }
        if let match = existing.first(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(name, options: .caseInsensitive) == .orderedSame
        }) {
            return .duplicate(existing: match)
        }
        return .valid(name)
    }
}
