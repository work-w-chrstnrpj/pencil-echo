import CryptoKit
import Foundation

// Document package schema v1 types. Contract: docs/database/document-schema-v1.md.
// These Codable types are authoritative; unknown JSON keys are ignored on decode.

enum DocumentSchema {
    static let currentVersion = 1
    static let packageExtension = "pencilecho"
    static let a4 = PageSize(width: 595, height: 842)
    static let newCanvasSize = PageSize(width: 2_000, height: 2_000)
}

enum DocumentLimits {
    static let maxTitleLength = 200
    static let maxNotebookPages = 500
    static let maxObjects = 5_000
    static let maxObjectsFileBytes = 32 * 1024 * 1024
    static let maxSourceBytes = 100 * 1024
    static let maxAssetBytes = 32 * 1024 * 1024
    static let maxAssetBytesPerDocument = 1024 * 1024 * 1024
    static let maxCanvasSide = 20_000.0
    static let minObjectSide = 8.0
    static let maxMessages = 2_000
    static let maxMessageBytes = 16 * 1024
}

enum DocumentType: String, Codable, Sendable {
    case canvas, notebook

    var defaultTitle: String { self == .canvas ? "Untitled Canvas" : "Untitled Notebook" }
}

struct DocumentManifest: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var id: UUID
    var type: DocumentType
    var title: String
    var revision: Int
    var createdAt: Date
    var updatedAt: Date
    /// Diagnostic only; never used for logic.
    var appVersion: String
    /// Optional v1 editor preferences. Missing values retain the previous behavior.
    var gridVisible: Bool? = nil
    var chatPanelOpen: Bool? = nil
    /// Optional v1 library metadata (ticket 022). Absent means not favorited and never opened.
    var isFavorite: Bool? = nil
    var lastOpenedAt: Date? = nil
}

struct PageSize: Codable, Equatable, Sendable {
    var width: Double
    var height: Double
}

enum BackgroundStyle: String, Codable, Sendable {
    case blank, lined, dotted, grid
}

struct PageBackground: Codable, Equatable, Sendable {
    static let defaultSpacing = 24.0
    static let blank = PageBackground(style: .blank, spacing: nil)

    var style: BackgroundStyle
    /// Points between lines or dots, 8–96; nil uses the default. Always nil for blank.
    var spacing: Double?

    // Encode nil explicitly so the file always has the key, as the spec shows.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(style, forKey: .style)
        try container.encode(spacing, forKey: .spacing)
    }
}

struct Page: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var size: PageSize
    var background: PageBackground
}

/// A rectangle in page points, origin top-left, y down.
struct PageRect: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

enum ObjectType: String, Codable, Sendable {
    /// `plot` (ticket 016): a function graph whose source is the `PlotSpec` line format.
    case text, markdown, latex, image, plot
}

enum ObjectCreator: Equatable, Sendable, Codable {
    case user
    case ai(requestId: UUID)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        if value == "user" {
            self = .user
        } else if value.hasPrefix("ai:"), let id = UUID(uuidString: String(value.dropFirst(3))) {
            self = .ai(requestId: id)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "createdBy must be user or ai:<uuid>"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .user: try container.encode("user")
        case .ai(let id): try container.encode("ai:" + id.uuidString)
        }
    }
}

struct DocumentObject: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var pageId: UUID
    var type: ObjectType
    var frame: PageRect
    var zIndex: Int
    /// Editable content. For images, the accessibility description.
    var source: String
    /// Asset names (`<sha256>.<ext>`). Images have exactly one.
    var assetRefs: [String]
    var createdBy: ObjectCreator
    var createdAt: Date
    var updatedAt: Date
    var aiAppearance: AIAnswerAppearance? = nil
    var isDraft: Bool? = nil
}

struct AppliedRequest: Codable, Equatable, Sendable {
    var requestId: UUID
    var appliedAt: Date
}

struct ConversationMessage: Codable, Equatable, Identifiable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }

    var id: UUID
    var role: Role
    var requestId: UUID?
    var text: String
    var createdAt: Date
}

struct Conversation: Codable, Equatable, Sendable {
    var appliedRequests: [AppliedRequest] = []
    var messages: [ConversationMessage] = []
}

// File wrappers, matching the JSON roots.
struct PagesFile: Codable, Equatable, Sendable { var pages: [Page] }
struct ObjectsFile: Codable, Equatable, Sendable { var objects: [DocumentObject] }

enum AssetName {
    static let allowedExtensions: Set<String> = ["png", "jpg", "heic", "pdf"]

    /// `<lowercase hex sha256>.<ext>`.
    static func make(for data: Data, extension ext: String) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + "." + ext
    }

    static func isValid(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, allowedExtensions.contains(String(parts[1])) else { return false }
        return parts[0].count == 64 && parts[0].allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}

/// A whole document in memory. Asset bytes already in the package stay on disk;
/// `pendingAssets` holds only bytes added since the last load.
struct Document: Equatable, Sendable {
    var manifest: DocumentManifest
    var pages: [Page]
    var objects: [DocumentObject]
    /// `PKDrawing.dataRepresentation()` per page, page-relative. Absent means no ink.
    var ink: [UUID: Data] = [:]
    var pendingAssets: [String: Data] = [:]
    var conversation: Conversation?
    var chat: AgentChatHistory? = nil
    var thumbnail: Data?
    /// Set when the package was migrated in memory from an older schema version.
    var migratedFrom: Int?

    var id: UUID { manifest.id }

    /// Every asset name referenced by an object.
    var referencedAssets: Set<String> { Set(objects.flatMap(\.assetRefs)) }
}

enum DocumentCoding {
    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(dateStyle))
        }
        return encoder
    }

    /// The schema's ISO 8601 UTC representation, for metadata written without a full encode.
    static func string(from date: Date) -> String {
        date.formatted(dateStyle)
    }

    static func date(from text: String) -> Date? {
        (try? Date(text, strategy: dateStyle)) ?? (try? Date(text, strategy: .iso8601))
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            guard let date = date(from: try container.decode(String.self)) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 date")
            }
            return date
        }
        return decoder
    }
}

/// Chat text is local to this document. No capture images or raw reasoning persist.
struct AgentChatHistory: Codable, Equatable, Sendable {
    var messages: [ConversationMessage] = []
    var draftInk: [DraftInkBatch] = []
    static let maxTurns = 10
    static let maxFileBytes = 512 * 1024
    mutating func append(user: String, assistant: String, requestId: UUID, at date: Date) {
        func clipped(_ text: String) -> String {
            var text = String(text.prefix(DocumentLimits.maxMessageBytes))
            while text.utf8.count > DocumentLimits.maxMessageBytes { text.removeLast() }
            return text
        }
        messages += [ConversationMessage(id: UUID(), role: .user, requestId: requestId, text: clipped(user), createdAt: date),
                     ConversationMessage(id: UUID(), role: .assistant, requestId: requestId, text: clipped(assistant), createdAt: date)]
        messages = Array(messages.suffix(Self.maxTurns * 2))
    }
    var isValid: Bool {
        messages.count <= Self.maxTurns * 2 && messages.count.isMultiple(of: 2) && messages.enumerated().allSatisfy {
            $0.element.text.utf8.count <= DocumentLimits.maxMessageBytes && $0.element.role == ($0.offset.isMultiple(of: 2) ? .user : .assistant)
        } && draftInk.count <= DocumentLimits.maxObjects && draftInk.allSatisfy { $0.strokeDate.timeIntervalSince1970 < 86_400 && $0.strokeDate.timeIntervalSince1970 != 0 }
    }
}

/// PencilKit preserves path.creationDate across serialization and transforms.
/// Draft strokes use a unique date in the first day of 1970 (ticket 023: PencilKit hides pre-1970 strokes), so Auto Ask never treats them as new user ink.
struct DraftInkBatch: Codable, Equatable, Sendable {
    var requestId: UUID
    var strokeDate: Date
}

/// Optional object style keeps existing packages readable without a schema bump.
struct AIAnswerAppearance: Codable, Equatable, Sendable {
    enum Font: String, Codable, CaseIterable, Sendable { case handwritten, rounded, system }
    enum Ink: String, Codable, CaseIterable, Sendable { case blue, black, gray, red, green, orange, purple, brown }
    var ink: Ink = .blue
    var font: Font = .handwritten
}
