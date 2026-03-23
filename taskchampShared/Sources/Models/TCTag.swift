import Foundation
import SwiftData

@Model
public class TCTag: Codable, Equatable {
    enum CodingKeys: CodingKey {
        case name
        case includedInFilters
        case excludedFromFilters
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
    }

    public required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        includedInFilters = try container.decodeIfPresent(
            [TCFilter].self,
            forKey: .includedInFilters
        ) ?? []
        excludedFromFilters = try container.decodeIfPresent(
            [TCFilter].self,
            forKey: .excludedFromFilters
        ) ?? []
    }

    public static func == (lhs: TCTag, rhs: TCTag) -> Bool {
        return lhs.name == rhs.name
    }

    public var name: String = ""

    public var includedInFilters: [TCFilter]?

    public var excludedFromFilters: [TCFilter]?

    @MainActor
    public static func tagFactory(name: String, addToCache: Bool = true) -> TCTag {
        let existingTag = SwiftDataService.shared.fetchTag(name: name)
        if let existingTag {
            NLPService.shared.appendTagsToCache([existingTag])
            return existingTag
        }
        let tag = TCTag(name: name)
        if addToCache {
            NLPService.shared.appendTagsToCache([tag])
        }
        return tag
    }

    public init(name: String) {
        self.name = name
        includedInFilters = []
        excludedFromFilters = []
    }

    public func isSynthetic() -> Bool {
        name.hasPrefix("_")
    }

    public func isValid() -> Bool {
        guard !name.isEmpty else { return false }
        let pattern = /^[a-zA-Z0-9._]+$/
        return name.wholeMatch(of: pattern) != nil && !isSynthetic()
    }
}
