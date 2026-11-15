import SwiftUI

@main
struct MoorApp: App {
    @StateObject private var model = BatteryViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            MenuBarLabel(info: model.info)
        }
        .menuBarExtraStyle(.menu)
    }
}
