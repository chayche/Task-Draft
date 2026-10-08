import SwiftUI

struct ContentView: View {
    var body: some View {
        UIKitHost {
            AppRootViewController()
        }
        .ignoresSafeArea()
        .persistentSystemOverlays(.visible)
        .statusBarHidden(true)
        .tint(Color(red: 11 / 255, green: 166 / 255, blue: 134 / 255))
    }
}

#Preview("iPhone") {
    ContentView()
}

#Preview("iPad") {
    ContentView()
}
