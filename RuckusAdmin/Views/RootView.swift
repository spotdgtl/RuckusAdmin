import SwiftUI

struct RootView: View {
    @Environment(ControllerStore.self) private var store

    var body: some View {
        Group {
            if store.isConnected {
                MainView()
            } else {
                LoginView()
            }
        }
        .animation(.default, value: store.isConnected)
    }
}
