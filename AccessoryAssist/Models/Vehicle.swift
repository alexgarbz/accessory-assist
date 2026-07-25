import Foundation

/// A vehicle line that accessories can be filtered against.
///
/// The set of valid vehicle ids is defined by the catalogue itself; the
/// validator rejects any product referencing an id that is not published here,
/// which is what stops a typo in the content file from silently hiding stock.
struct Vehicle: Decodable, Identifiable, Hashable {
    static let universalId = "universal"

    let id: String
    let name: String
    let order: Int

    init(id: String, name: String, order: Int = 0) {
        self.id = id
        self.name = name
        self.order = order
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, order
    }

    var isUniversal: Bool { id == Vehicle.universalId }
}

/// A merchandising category, e.g. Interior or Charging.
struct ProductCategory: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let order: Int

    init(id: String, name: String, order: Int = 0) {
        self.id = id
        self.name = name
        self.order = order
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, order
    }
}
