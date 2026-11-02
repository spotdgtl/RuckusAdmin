import Foundation

struct ListColumn: Sendable, Identifiable {
    var id: String { key }
    var key: String
    var title: String
    var width: CGFloat?

    init(_ key: String, _ title: String, width: CGFloat? = nil) {
        self.key = key
        self.title = title
        self.width = width
    }
}

/// One row of a list component, kept as raw attributes plus child elements.
struct ListRow: Identifiable, Sendable, Hashable {
    var id: String
    var attributes: [String: String]
    var children: [XMLNode]

    subscript(key: String) -> String { attributes[key] ?? "" }
    var isEditable: Bool { (attributes["EDITABLE"] ?? "true").lowercased() != "false" }
}

struct ListPageSpec: Identifiable, Sendable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var component: String
    var element: String
    var readAction: AjaxRequest.Action = .getconf
    var decrypt = false
    /// For lists served by `getstat`, the body to send (e.g. `<dpsk-list/>`).
    var statBody: String?
    var columns: [ListColumn]
    var fields: [ConfigField]
    var canAdd = true
    var canEdit = true
    var canDelete = true
    var idAttribute = "id"
    var note: String?

    var elementPath: String { element }
}
