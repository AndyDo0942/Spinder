import SwiftUI

struct ContentView: View {
    @AppStorage("didOnboard") private var didOnboard = false

    var body: some View {
        if didOnboard {
            SongSwipeHome()
        } else {
            DreamOnboarding()
        }
    }
}

#Preview { ContentView() }
