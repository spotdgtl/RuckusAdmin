import SwiftUI

struct SettingsGroupView: View {
    @Environment(ControllerStore.self) private var store
    var group: SettingsGroup
    @State private var selectedPageID: String?

    private var selectedPage: SettingsPage? {
        group.pages.first { $0.id == selectedPageID } ?? group.pages.first
    }

    var body: some View {
        HSplitView {
            List(group.pages, selection: $selectedPageID) { page in
                Label(page.title, systemImage: page.systemImage)
                    .tag(page.id)
            }
            .listStyle(.inset)
            .frame(minWidth: 200, idealWidth: 230, maxWidth: 280)

            Group {
                if let page = selectedPage {
                    SettingsPageContent(page: page)
                        .id(page.id)
                } else {
                    ContentUnavailableView("Choose a page", systemImage: group.systemImage)
                }
            }
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(group.title)
        .navigationSubtitle(store.isDemo ? "Demo mode: changes stay in memory" : "Changes are applied to \(store.settings.host)")
        .onAppear {
            if selectedPageID == nil { selectedPageID = group.pages.first?.id }
        }
    }
}

struct SettingsPageContent: View {
    var page: SettingsPage

    var body: some View {
        switch page.content {
        case .config(let spec):
            ConfigPageView(spec: spec)
        case .list(let spec):
            ListPageView(spec: spec)
        case .composite(let config, let lists):
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let config {
                        ConfigPageView(spec: config, embedded: true)
                    }
                    ForEach(lists) { list in
                        ListPageView(spec: list, embedded: true)
                    }
                }
                .padding(20)
            }
        case .custom(let kind):
            switch kind {
            case .preferences: PreferencesView()
            case .backupRestore: BackupRestoreView()
            case .upgrade: UpgradeView()
            case .diagnostics: DiagnosticsView()
            case .certificate: CertificateView()
            case .technicalSupport: TechnicalSupportView()
            }
        }
    }
}
