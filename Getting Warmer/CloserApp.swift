//
//  CloserApp.swift
//  Closer
//
//  Created by Ryan O'Sullivan on 4/18/26.
//

import SwiftUI

@main
struct CloserApp: App {
    @State private var puzzleStore = PuzzleStore()
    @State private var locationManager = LocationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(puzzleStore)
                .environment(locationManager)
        }
    }
}
