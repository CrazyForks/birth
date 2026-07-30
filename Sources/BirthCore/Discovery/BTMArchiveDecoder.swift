import Foundation

/// Decodes Apple's NSKeyedArchiver-based Background Task Management store
/// without loading private frameworks or launching `sfltool`.
enum BTMArchiveDecoder {
    static func decode(_ data: Data, accountIdentifier: String) throws -> [BTMItem] {
        let archivedClasses = try archivedClassNames(in: data)
        let storageNames = archivedClasses.filter { classBaseName($0) == "Storage" }
        let recordNames = archivedClasses.filter {
            let name = classBaseName($0)
            return name == "ItemRecord" || name == "BTMItem"
        }
        // A legitimate empty store has no archived ItemRecord class at all.
        // Storage is the only class that must always be present.
        guard !storageNames.isEmpty else {
            throw BTMReader.BTMError.unsupportedFormat(
                detail: "Missing Storage archive class"
            )
        }

        let unarchiver: NSKeyedUnarchiver
        do {
            unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        } catch {
            throw BTMReader.BTMError.unsupportedFormat(
                detail: "Unarchiver initialization: \(error.localizedDescription)"
            )
        }
        // The BTM archive is root-owned and protected by TCC. Apple has
        // changed otherwise equivalent Foundation representations between
        // releases (for example UUID/string and set/array). We still map only
        // the two BTM model classes and decode only fields Birth consumes,
        // but do not make one representation mismatch reject the whole store.
        unarchiver.requiresSecureCoding = false
        unarchiver.decodingFailurePolicy = .setErrorAndReturn
        storageNames.forEach { unarchiver.setClass(BTMArchiveStorage.self, forClassName: $0) }
        recordNames.forEach { unarchiver.setClass(BTMArchiveRecord.self, forClassName: $0) }

        guard let storage = unarchiver.decodeObject(forKey: "store") as? BTMArchiveStorage else {
            let detail = unarchiver.error?.localizedDescription ?? "Missing root 'store' object"
            unarchiver.finishDecoding()
            throw BTMReader.BTMError.unsupportedFormat(detail: "Storage decoding: \(detail)")
        }
        unarchiver.finishDecoding()
        if let error = unarchiver.error {
            throw BTMReader.BTMError.unsupportedFormat(
                detail: "Archive completion: \(error.localizedDescription)"
            )
        }

        let records = storage.itemsByUserIdentifier.first {
            $0.key.caseInsensitiveCompare(accountIdentifier) == .orderedSame
        }?.value ?? []
        return makeItems(from: records)
    }

    /// Read only the archive's class table before decoding. This lets module-
    /// qualified class names evolve while keeping the accepted semantic names
    /// narrow; arbitrary archived classes are never registered or instantiated.
    private static func archivedClassNames(in data: Data) throws -> [String] {
        let root: Any
        do {
            root = try PropertyListSerialization.propertyList(from: data, format: nil)
        } catch {
            throw BTMReader.BTMError.unsupportedFormat(
                detail: "Property-list inspection: \(error.localizedDescription)"
            )
        }
        guard let archive = root as? [String: Any],
              archive["$archiver"] as? String == "NSKeyedArchiver",
              let objects = archive["$objects"] as? [Any]
        else {
            throw BTMReader.BTMError.unsupportedFormat(detail: "Not an NSKeyedArchiver store")
        }
        return objects.compactMap { object in
            (object as? [String: Any])?["$classname"] as? String
        }
    }

    private static func classBaseName(_ name: String) -> String {
        name.split(separator: ".").last.map(String.init) ?? name
    }

    private static func makeItems(from records: [BTMArchiveRecord]) -> [BTMItem] {
        let parents = Dictionary(
            records.compactMap { record in
                record.identifier.map { ($0, record) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        return records.compactMap { record in
            guard let kind = modernKind(for: record.type) else { return nil }
            let fallbackID = record.identifier
                ?? record.bundleIdentifier
                ?? record.url?.absoluteString
                ?? "type-\(record.type)"
            return BTMItem(
                uuid: record.uuid?.uuidString ?? fallbackID,
                name: record.name,
                developerName: record.developerName,
                teamIdentifier: record.teamIdentifier,
                typeDescription: kind.description,
                isEnabled: record.disposition & 0x1 != 0,
                identifier: record.identifier,
                urlString: record.url?.absoluteString,
                executablePath: executablePath(
                    for: record,
                    kind: kind,
                    parent: record.container.flatMap { parents[$0] }
                ),
                bundleIdentifier: record.bundleIdentifier,
                parentIdentifier: record.container,
                embeddedItemIdentifiers: record.embeddedItems.sorted()
            )
        }
    }

    private enum ModernKind {
        case app
        case loginItem
        case agent
        case daemon
        case backgroundAppRefresh

        var description: String {
            switch self {
            case .app: "app"
            case .loginItem: "login item"
            case .agent: "agent"
            case .daemon: "daemon"
            case .backgroundAppRefresh: "background app refresh"
            }
        }
    }

    private static func modernKind(for rawType: Int) -> ModernKind? {
        // Legacy launchd records duplicate Birth's plist scan and grouping
        // records are metadata, not runnable items.
        guard rawType & 0x10000 == 0 else { return nil }
        if rawType & 0x2 != 0 { return .app }
        if rawType & 0x4 != 0 { return .loginItem }
        if rawType & 0x8 != 0 { return .agent }
        if rawType & 0x10 != 0 { return .daemon }
        if rawType & 0x1000 != 0 { return .backgroundAppRefresh }
        return nil
    }

    private static func executablePath(
        for record: BTMArchiveRecord,
        kind: ModernKind,
        parent: BTMArchiveRecord?
    ) -> String? {
        if let executablePath = record.executablePath, !executablePath.isEmpty {
            return executablePath
        }
        guard let url = record.url else { return nil }

        switch kind {
        case .app, .backgroundAppRefresh:
            return bundleExecutableOrPath(url)
        case .loginItem:
            if url.isFileURL { return bundleExecutableOrPath(url) }
            guard let parentURL = parent?.url, parentURL.isFileURL else { return nil }
            let childURL = parentURL.appending(path: url.relativeString)
            return bundleExecutableOrPath(childURL)
        case .agent, .daemon:
            return nil
        }
    }

    private static func bundleExecutableOrPath(_ url: URL) -> String? {
        guard url.isFileURL else { return nil }
        return Bundle(url: url)?.executableURL?.path ?? url.path
    }
}

/// Local stand-ins for the two private model classes named in the archive.
/// Decoding never loads Apple's private daemon executable.
final class BTMArchiveStorage: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    let itemsByUserIdentifier: [String: [BTMArchiveRecord]]

    init(itemsByUserIdentifier: [String: [BTMArchiveRecord]]) {
        self.itemsByUserIdentifier = itemsByUserIdentifier
    }

    required init?(coder: NSCoder) {
        guard let items = coder.decodeObject(forKey: "itemsByUserIdentifier")
            as? [String: [BTMArchiveRecord]] else { return nil }
        itemsByUserIdentifier = items
    }

    func encode(with coder: NSCoder) {
        coder.encode(itemsByUserIdentifier, forKey: "itemsByUserIdentifier")
    }
}

final class BTMArchiveRecord: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }

    let uuid: UUID?
    let name: String?
    let developerName: String?
    let teamIdentifier: String?
    let type: Int
    let disposition: Int
    let identifier: String?
    let url: URL?
    let executablePath: String?
    let bundleIdentifier: String?
    let container: String?
    let embeddedItems: Set<String>
    let associatedBundleIdentifiers: [String]

    init(
        uuid: UUID? = nil,
        name: String? = nil,
        developerName: String? = nil,
        teamIdentifier: String? = nil,
        type: Int,
        disposition: Int,
        identifier: String? = nil,
        url: URL? = nil,
        executablePath: String? = nil,
        bundleIdentifier: String? = nil,
        container: String? = nil,
        embeddedItems: Set<String> = [],
        associatedBundleIdentifiers: [String] = []
    ) {
        self.uuid = uuid
        self.name = name
        self.developerName = developerName
        self.teamIdentifier = teamIdentifier
        self.type = type
        self.disposition = disposition
        self.identifier = identifier
        self.url = url
        self.executablePath = executablePath
        self.bundleIdentifier = bundleIdentifier
        self.container = container
        self.embeddedItems = embeddedItems
        self.associatedBundleIdentifiers = associatedBundleIdentifiers
    }

    required init?(coder: NSCoder) {
        let archivedUUID = coder.decodeObject(forKey: "uuid")
        if let value = archivedUUID as? UUID {
            uuid = value
        } else if let value = archivedUUID as? String {
            uuid = UUID(uuidString: value)
        } else {
            uuid = nil
        }
        name = coder.decodeObject(forKey: "name") as? String
        developerName = coder.decodeObject(forKey: "developerName") as? String
        teamIdentifier = coder.decodeObject(forKey: "teamIdentifier") as? String
        type = coder.decodeInteger(forKey: "type")
        disposition = coder.decodeInteger(forKey: "disposition")
        identifier = coder.decodeObject(forKey: "identifier") as? String
        let archivedURL = coder.decodeObject(forKey: "url")
        if let value = archivedURL as? URL {
            url = value
        } else if let value = archivedURL as? String {
            url = URL(string: value)
        } else {
            url = nil
        }
        executablePath = coder.decodeObject(forKey: "executablePath") as? String
        bundleIdentifier = coder.decodeObject(forKey: "bundleIdentifier") as? String
        container = coder.decodeObject(forKey: "container") as? String
        let archivedItems = coder.decodeObject(forKey: "items")
        if let values = archivedItems as? Set<String> {
            embeddedItems = values
        } else if let values = archivedItems as? [String] {
            embeddedItems = Set(values)
        } else {
            embeddedItems = []
        }
        let archivedBundleIdentifiers = coder.decodeObject(
            forKey: "associatedBundleIdentifiers"
        )
        if let values = archivedBundleIdentifiers as? [String] {
            associatedBundleIdentifiers = values
        } else if let values = archivedBundleIdentifiers as? Set<String> {
            associatedBundleIdentifiers = values.sorted()
        } else {
            associatedBundleIdentifiers = []
        }
    }

    func encode(with coder: NSCoder) {
        coder.encode(uuid, forKey: "uuid")
        coder.encode(name, forKey: "name")
        coder.encode(developerName, forKey: "developerName")
        coder.encode(teamIdentifier, forKey: "teamIdentifier")
        coder.encode(type, forKey: "type")
        coder.encode(disposition, forKey: "disposition")
        coder.encode(identifier, forKey: "identifier")
        coder.encode(url, forKey: "url")
        coder.encode(executablePath, forKey: "executablePath")
        coder.encode(bundleIdentifier, forKey: "bundleIdentifier")
        coder.encode(container, forKey: "container")
        coder.encode(embeddedItems as NSSet, forKey: "items")
        coder.encode(associatedBundleIdentifiers, forKey: "associatedBundleIdentifiers")
    }
}
