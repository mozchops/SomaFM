import SwiftUI

@main
struct SomaFMiOSApp: App {
    @State private var model = SomaFMModel()

    var body: some Scene {
        WindowGroup {
            SomaFMView(model: model)
                .task { model.start() }
        }
    }
}
