//
//  ContentView.swift
//  SwipeTune
//
//  Created by Anatoli Monsalve and Ethan Chen on 9/19/25.
//
import SwiftUI
struct ContentView: View {
    @AppStorage("didOnboard") private var didOnboard = false
    var body: some View {
        if didOnboard {
            SongSwipeHome()    // or RootAppView() if you want the playlist sheet path
        } else {
            RootAppView()      // includes the “Import Playlist Link” option
        }
    }
}
#Preview { ContentView() }
