import Foundation

/// The package's JSON files, decoded but untyped, keyed by file name
/// (`manifest.json`, `pages.json`, `objects.json`, `conversation.json`).
/// Migrations rewrite these before typed decoding.
struct RawPackage: @unchecked Sendable {
    var files: [String: [String: Any]]
}

/// Migration hook (docs/database/document-schema-v1.md, Migration). v1 has no
/// migrations: 1 → 1 returns its input. Each step upgrades one version and must
/// set `manifest.json` `schemaVersion` itself.
struct DocumentMigrator: Sendable {
    typealias Step = @Sendable (RawPackage) throws -> RawPackage

    enum MigrationError: Error, Equatable {
        case noPath(from: Int, to: Int)
        case stepDidNotUpgrade(from: Int)
    }

    static let standard = DocumentMigrator(steps: [:])

    /// `steps[n]` upgrades version n to n + 1.
    var steps: [Int: Step]

    func migrate(_ raw: RawPackage, from: Int, to: Int) throws -> RawPackage {
        guard from <= to else { throw MigrationError.noPath(from: from, to: to) }
        var package = raw
        for version in from..<to {
            guard let step = steps[version] else { throw MigrationError.noPath(from: from, to: to) }
            package = try step(package)
            guard package.files["manifest.json"]?["schemaVersion"] as? Int == version + 1 else {
                throw MigrationError.stepDidNotUpgrade(from: version)
            }
        }
        return package
    }
}
