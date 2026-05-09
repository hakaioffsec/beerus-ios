import Foundation

struct FridaScriptModel: Codable, Identifiable {
    let id: UUID
    var name: String
    var source: String
    var createdAt: Date
    var updatedAt: Date
    var targetBundle: String?

    init(name: String, source: String = "", targetBundle: String? = nil) {
        self.id = UUID()
        self.name = name
        self.source = source
        self.createdAt = Date()
        self.updatedAt = Date()
        self.targetBundle = targetBundle
    }
}
