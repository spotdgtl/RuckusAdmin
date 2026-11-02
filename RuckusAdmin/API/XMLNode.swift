import Foundation

/// A small, value-typed XML tree. The Ruckus AJAX API returns flat XML where almost
/// everything of interest lives in element attributes, so this keeps lookups cheap and
/// lets the rest of the app stay `Sendable`.
struct XMLNode: Sendable, Hashable {
    var name: String
    var attributes: [String: String] = [:]
    var children: [XMLNode] = []
    var text: String = ""

    init(name: String, attributes: [String: String] = [:], children: [XMLNode] = [], text: String = "") {
        self.name = name
        self.attributes = attributes
        self.children = children
        self.text = text
    }

    /// Attribute lookup, e.g. `node["mac"]`.
    subscript(attribute: String) -> String? {
        attributes[attribute]
    }

    /// First attribute value found among several candidate names.
    func attr(_ names: String...) -> String? {
        for name in names {
            if let value = attributes[name], !value.isEmpty { return value }
        }
        return nil
    }

    func first(_ name: String) -> XMLNode? {
        children.first { $0.name == name }
    }

    func all(_ name: String) -> [XMLNode] {
        children.filter { $0.name == name }
    }

    /// Depth-first search for the first descendant with the given element name.
    func firstDescendant(named name: String) -> XMLNode? {
        for child in children {
            if child.name == name { return child }
            if let found = child.firstDescendant(named: name) { return found }
        }
        return nil
    }

    /// Every descendant (any depth) with the given element name.
    func descendants(named name: String) -> [XMLNode] {
        var result: [XMLNode] = []
        for child in children {
            if child.name == name { result.append(child) }
            result.append(contentsOf: child.descendants(named: name))
        }
        return result
    }

    /// A pretty-printed rendering used by the API explorer and diagnostics export.
    func prettyPrinted(indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        let attrs = attributes
            .sorted { $0.key < $1.key }
            .map { " \($0.key)=\"\(XMLNode.escape($0.value))\"" }
            .joined()
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if children.isEmpty && trimmedText.isEmpty {
            return "\(pad)<\(name)\(attrs)/>"
        }
        var lines = ["\(pad)<\(name)\(attrs)>"]
        if !trimmedText.isEmpty {
            lines.append("\(pad)  \(XMLNode.escape(trimmedText))")
        }
        for child in children {
            lines.append(child.prettyPrinted(indent: indent + 1))
        }
        lines.append("\(pad)</\(name)>")
        return lines.joined(separator: "\n")
    }

    static func escape(_ string: String) -> String {
        var out = ""
        out.reserveCapacity(string.count)
        for ch in string {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(ch)
            }
        }
        return out
    }
}

enum XMLParseError: LocalizedError {
    case empty
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .empty: return "The controller returned an empty response."
        case .malformed(let detail): return "The controller returned XML that could not be parsed: \(detail)"
        }
    }
}

/// Builds an `XMLNode` tree with Foundation's streaming `XMLParser`.
final class XMLTreeParser: NSObject, XMLParserDelegate {
    private var stack: [XMLNode] = []
    private var root: XMLNode?
    private var failure: String?

    static func parse(_ string: String) throws -> XMLNode {
        let cleaned = sanitize(string)
        guard !cleaned.isEmpty else { throw XMLParseError.empty }
        guard let data = cleaned.data(using: .utf8) else { throw XMLParseError.malformed("not UTF-8") }
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> XMLNode {
        guard !data.isEmpty else { throw XMLParseError.empty }
        let delegate = XMLTreeParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        let ok = parser.parse()
        if let root = delegate.root, ok || delegate.failure == nil {
            return root
        }
        if let root = delegate.root { return root }
        let message = delegate.failure ?? parser.parserError?.localizedDescription ?? "unknown error"
        throw XMLParseError.malformed(message)
    }

    /// The controller occasionally emits bare ampersands and control characters inside
    /// attribute values; `XMLParser` rejects both, so repair them before parsing.
    static func sanitize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("\u{FEFF}") { s.removeFirst() }
        // Drop everything before the first '<' (stray whitespace, BOM, HTTP junk).
        if let lt = s.firstIndex(of: "<"), lt != s.startIndex {
            s = String(s[lt...])
        }
        // Escape ampersands that do not start a valid entity reference.
        if s.contains("&") {
            let pattern = #"&(?!(amp|lt|gt|quot|apos|#[0-9]+|#x[0-9a-fA-F]+);)"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(s.startIndex..., in: s)
                s = regex.stringByReplacingMatches(in: s, range: range, withTemplate: "&amp;")
            }
        }
        // Remove control characters that XML 1.0 forbids.
        let forbidden = s.unicodeScalars.contains { scalar in
            scalar.value < 0x20 && scalar != "\t" && scalar != "\n" && scalar != "\r"
        }
        if forbidden {
            let filtered = s.unicodeScalars.filter { scalar in
                !(scalar.value < 0x20 && scalar != "\t" && scalar != "\n" && scalar != "\r")
            }
            s = String(String.UnicodeScalarView(filtered))
        }
        return s
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        stack.append(XMLNode(name: elementName, attributes: attributeDict))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !stack.isEmpty else { return }
        stack[stack.count - 1].text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard !stack.isEmpty, let text = String(data: CDATABlock, encoding: .utf8) else { return }
        stack[stack.count - 1].text += text
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard let node = stack.popLast() else { return }
        if stack.isEmpty {
            root = node
        } else {
            stack[stack.count - 1].children.append(node)
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        failure = parseError.localizedDescription
        // Keep whatever was parsed so far: Ruckus responses sometimes have trailing junk.
        while stack.count > 1 {
            let node = stack.removeLast()
            stack[stack.count - 1].children.append(node)
        }
        if root == nil, let node = stack.first { root = node }
    }
}
