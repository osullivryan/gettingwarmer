//
//  ContentView.swift
//  Closer
//
//  Created by Ryan O'Sullivan on 4/18/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        HomeView()
    }
}

#Preview {
    ContentView()
        .environment(PuzzleStore())
        .environment(LocationManager())
}
