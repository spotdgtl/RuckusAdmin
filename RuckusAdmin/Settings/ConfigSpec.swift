import Foundation

// MARK: - Field and page descriptions

struct ConfigOption: Sendable, Hashable, Identifiable {
    var id: String { value }
    var value: String
    var label: String

    init(_ value: String, _ label: String) {
        self.value = value
        self.label = label
    }
}

/// Picker options that come from the controller (a list component) or from the live network.
struct DynamicOptions: Sendable {
    enum Source: Sendable {
        case list(component: String, element: String, valueAttribute: String, labelAttribute: String)
        case accessPoints
    }

    var source: Source
    var includeNone: ConfigOption?
}

enum ConfigFieldKind: Sendable {
    case text
    case number(ClosedRange<Int>)
    case toggle(on: String, off: String)
    case picker([ConfigOption])
    case dynamicPicker(DynamicOptions)
    case password
    case readOnly
    case readOnlyDate
    case multiline
}

struct ConfigField: Identifiable, Sendable {
    var id: String { "\(path)@\(key)" }
    /// Element path such as `mgmt-ip`, `ap-policy/zd-ip` or `client-load-balancing/radio[radio-id=0]`.
    var path: String
    var key: String
    var label: String
    var kind: ConfigFieldKind
    var help: String?
    var visibleWhen: (@Sendable (ConfigValues) -> Bool)?

    init(_ path: String, _ key: String, _ label: String, _ kind: ConfigFieldKind = .text,
         help: String? = nil, visibleWhen: (@Sendable (ConfigValues) -> Bool)? = nil) {
        self.path = path
        self.key = key
        self.label = label
        self.kind = kind
        self.help = help
        self.visibleWhen = visibleWhen
    }

    var isEditable: Bool {
        switch kind {
        case .readOnly, .readOnlyDate: return false
        default: return true
        }
    }
}

struct ConfigSection: Identifiable, Sendable {
    var id: String { title }
    var title: String
    var footer: String?
    var fields: [ConfigField]

    init(_ title: String, footer: String? = nil, _ fields: [ConfigField]) {
        self.title = title
        self.footer = footer
        self.fields = fields
    }
}

/// How a top-level element on a page is written back.
struct ConfigWrite: Sendable {
    enum Kind: Sendable {
        /// `setconf comp='system'` with the element inside the request.
        case systemSetconf
        /// `updobj` on a list component, element identified by `idAttribute`.
        case updobj(component: String)
    }

    var path: String
    var kind: Kind = .systemSetconf
    var partial = true
    var constants: [String: String] = [:]
    var childConstants: [String: [String: String]] = [:]
    var idAttribute = "id"

    init(_ path: String, kind: Kind = .systemSetconf, partial: Bool = true,
         constants: [String: String] = [:], childConstants: [String: [String: String]] = [:]) {
        self.path = path
        self.kind = kind
        self.partial = partial
        self.constants = constants
        self.childConstants = childConstants
    }
}

/// An extra read from a list component whose first element is exposed under `alias`.
struct ConfigListRead: Sendable {
    var component: String
    var element: String
    var alias: String
    var decrypt = false
}

struct ConfigPageSpec: Identifiable, Sendable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var readElements: [String]
    var readAction: AjaxRequest.Action = .getstat
    var listReads: [ConfigListRead] = []
    var sections: [ConfigSection]
    var writes: [ConfigWrite]
    var applyWarning: String?

    var fields: [ConfigField] { sections.flatMap(\.fields) }
}

// MARK: - Values

struct ConfigValues: Sendable, Equatable {
    var attributes: [String: [String: String]] = [:]

    subscript(path: String, key: String) -> String {
        get { attributes[path]?[key] ?? "" }
        set { attributes[path, default: [:]][key] = newValue }
    }

    func bool(_ path: String, _ key: String) -> Bool {
        RuckusParsers.bool(self[path, key])
    }

    func has(_ path: String) -> Bool {
        attributes[path] != nil
    }
}

// MARK: - Path resolution and XML building

enum ConfigPath {
    struct Component: Sendable, Equatable {
        var name: String
        var predicateKey: String?
        var predicateValue: String?
    }

    static func components(of path: String) -> [Component] {
        path.split(separator: "/").map { part in
            let text = String(part)
            if let open = text.firstIndex(of: "["), text.hasSuffix("]") {
                let name = String(text[..<open])
                let inner = text[text.index(after: open)..<text.index(before: text.endIndex)]
                let pair = inner.split(separator: "=", maxSplits: 1).map(String.init)
                return Component(name: name, predicateKey: pair.first, predicateValue: pair.count > 1 ? pair[1] : nil)
            }
            return Component(name: text, predicateKey: nil, predicateValue: nil)
        }
    }

    /// Finds the node for `path` below `root`. The first component is searched at any depth.
    static func resolve(_ path: String, in root: XMLNode) -> XMLNode? {
        let parts = components(of: path)
        guard let first = parts.first else { return nil }
        var candidates = root.descendants(named: first.name)
        if let key = first.predicateKey {
            candidates = candidates.filter { $0[key] == first.predicateValue }
        }
        guard var node = candidates.first else { return nil }
        for part in parts.dropFirst() {
            var children = node.all(part.name)
            if let key = part.predicateKey {
                children = children.filter { $0[key] == part.predicateValue }
            }
            guard let next = children.first else { return nil }
            node = next
        }
        return node
    }

    static func read(spec: ConfigPageSpec, from root: XMLNode, lists: [String: XMLNode]) -> ConfigValues {
        var values = ConfigValues()
        for path in Set(spec.fields.map(\.path)) {
            let top = components(of: path).first?.name ?? path
            if let listRoot = lists[top] {
                let rest = components(of: path).dropFirst().map(render)
                let node = rest.isEmpty ? listRoot : resolve(rest.joined(separator: "/"), in: listRoot)
                if let node { values.attributes[path] = node.attributes }
            } else if let node = resolve(path, in: root) {
                values.attributes[path] = node.attributes
            }
        }
        return values
    }

    static func render(_ component: Component) -> String {
        if let key = component.predicateKey, let value = component.predicateValue {
            return "\(component.name)[\(key)=\(value)]"
        }
        return component.name
    }

    /// Builds the XML for one top-level write from the edited values.
    static func xml(for write: ConfigWrite, spec: ConfigPageSpec, values: ConfigValues, original: ConfigValues) -> String {
        let topName = components(of: write.path).first?.name ?? write.path
        let relevant = spec.fields.filter { field in
            guard field.isEditable, field.path == write.path || field.path.hasPrefix(write.path + "/") else { return false }
            // Blank password fields mean "keep the current secret"; never send them.
            if case .password = field.kind, values[field.path, field.key].isEmpty { return false }
            return true
        }
        guard !relevant.isEmpty else { return "" }
        // Untouched elements are left alone so a change on one section cannot disturb another.
        let changed = relevant.contains { values[$0.path, $0.key] != original[$0.path, $0.key] }
        guard changed else { return "" }

        var topAttrs: [(String, String)] = []
        var childGroups: [String: [(String, String)]] = [:]
        var childOrder: [String] = []
        for field in relevant {
            let value = values[field.path, field.key]
            if field.path == write.path {
                topAttrs.append((field.key, value))
            } else {
                let childPath = String(field.path.dropFirst(write.path.count + 1))
                if childGroups[childPath] == nil { childOrder.append(childPath) }
                childGroups[childPath, default: []].append((field.key, value))
            }
        }
        if case .updobj = write.kind {
            let id = original[write.path, write.idAttribute]
            if !id.isEmpty { topAttrs.insert((write.idAttribute, id), at: 0) }
        }
        for (key, value) in write.constants.sorted(by: { $0.key < $1.key }) where !topAttrs.contains(where: { $0.0 == key }) {
            topAttrs.append((key, value))
        }
        if write.partial {
            topAttrs.append(("IS_PARTIAL", "true"))
        }
        var xml = "<\(topName)\(attributeString(topAttrs))"
        if childOrder.isEmpty {
            return xml + "/>"
        }
        xml += ">"
        for childPath in childOrder {
            var attrs = childGroups[childPath] ?? []
            let parts = components(of: childPath)
            if let last = parts.last, let key = last.predicateKey, let value = last.predicateValue,
               !attrs.contains(where: { $0.0 == key }) {
                attrs.insert((key, value), at: 0)
            }
            for (key, value) in (write.childConstants[childPath] ?? [:]).sorted(by: { $0.key < $1.key }) where !attrs.contains(where: { $0.0 == key }) {
                attrs.append((key, value))
            }
            // Nested paths deeper than one level are emitted as nested elements.
            let names = parts.map(\.name)
            var open = ""
            var close = ""
            for (index, name) in names.enumerated() {
                if index == names.count - 1 {
                    open += "<\(name)\(attributeString(attrs))/>"
                } else {
                    open += "<\(name)>"
                    close = "</\(name)>" + close
                }
            }
            xml += open + close
        }
        xml += "</\(topName)>"
        return xml
    }

    static func attributeString(_ attrs: [(String, String)]) -> String {
        attrs.map { " \($0.0)='\(XMLNode.escape($0.1))'" }.joined()
    }
}

// MARK: - Common option sets

enum ConfigOptions {
    static let enabledDisabled: ConfigFieldKind = .toggle(on: "enabled", off: "disabled")
    static let trueFalse: ConfigFieldKind = .toggle(on: "true", off: "false")
    static let oneZero: ConfigFieldKind = .toggle(on: "1", off: "0")

    static let languages: [ConfigOption] = [
        ConfigOption("en_US", "English"), ConfigOption("zh_CN", "Chinese (Simplified)"), ConfigOption("zh_TW", "Chinese (Traditional)"),
        ConfigOption("fr_FR", "French"), ConfigOption("de_DE", "German"), ConfigOption("ja_JP", "Japanese"),
        ConfigOption("es_ES", "Spanish"), ConfigOption("se_SE", "Swedish"), ConfigOption("tr_TR", "Turkish"), ConfigOption("it_IT", "Italian"),
    ]

    static let countries: [ConfigOption] = [
        ("US", "United States"), ("GB", "United Kingdom"), ("CA", "Canada"), ("AU", "Australia"), ("NZ", "New Zealand"), ("IE", "Ireland"),
        ("DE", "Germany"), ("FR", "France"), ("ES", "Spain"), ("IT", "Italy"), ("NL", "Netherlands"), ("BE", "Belgium"), ("CH", "Switzerland"),
        ("AT", "Austria"), ("SE", "Sweden"), ("NO", "Norway"), ("DK", "Denmark"), ("FI", "Finland"), ("PL", "Poland"), ("CZ", "Czech Republic"),
        ("PT", "Portugal"), ("GR", "Greece"), ("HU", "Hungary"), ("RO", "Romania"), ("TR", "Türkiye"), ("IL", "Israel"), ("AE", "United Arab Emirates"),
        ("SA", "Saudi Arabia"), ("ZA", "South Africa"), ("IN", "India"), ("SG", "Singapore"), ("MY", "Malaysia"), ("TH", "Thailand"), ("ID", "Indonesia"),
        ("PH", "Philippines"), ("VN", "Vietnam"), ("JP", "Japan"), ("KR", "South Korea"), ("TW", "Taiwan"), ("HK", "Hong Kong"), ("CN", "China"),
        ("MX", "Mexico"), ("BR", "Brazil"), ("AR", "Argentina"), ("CL", "Chile"), ("CO", "Colombia"),
    ].map { ConfigOption($0.0, $0.1) }

    static let timezones = DynamicOptions(source: .list(component: "timezone-list", element: "timezone", valueAttribute: "key", labelAttribute: "value"))
    static let roles = DynamicOptions(source: .list(component: "role-list", element: "role", valueAttribute: "id", labelAttribute: "name"))
    static let accessPoints = DynamicOptions(source: .accessPoints, includeNone: ConfigOption("0", "No preference"))
}
