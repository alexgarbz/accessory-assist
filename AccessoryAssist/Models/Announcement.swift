import Foundation

/// Operational notice published with the catalogue. Used for stock notes,
/// pricing changes and sales guidance — never for marketing copy.
struct Announcement: Decodable, Identifiable, Hashable {
    enum Severity: String, Decodable, Hashable {
        case info
        case warning
        case critical

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Severity(rawValue: raw) ?? .info
        }

        var priority: Int {
            switch self {
            case .info: return 0
            case .warning: return 1
            case .critical: return 2
            }
        }
    }

    let id: String
    let title: String
    let body: String
    let severity: Severity
    let startsAt: Date?
    let endsAt: Date?
    let pinned: Bool

    private enum CodingKeys: String, CodingKey {
        case id, title, body, severity, startsAt, endsAt, pinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        severity = try container.decodeIfPresent(Severity.self, forKey: .severity) ?? .info
        startsAt = try container.decodeIfPresent(Date.self, forKey: .startsAt)
        endsAt = try container.decodeIfPresent(Date.self, forKey: .endsAt)
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }

    init(
        id: String,
        title: String,
        body: String = "",
        severity: Severity = .info,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        pinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.severity = severity
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.pinned = pinned
    }

    func isLive(at date: Date = Date()) -> Bool {
        if let startsAt, date < startsAt { return false }
        if let endsAt, date > endsAt { return false }
        return true
    }
}
