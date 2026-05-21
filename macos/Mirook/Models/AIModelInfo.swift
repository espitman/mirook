import Foundation

struct AIModelInfo: Identifiable, Codable, Equatable {
    let id: String

    var displayName: String {
        id
    }
}

