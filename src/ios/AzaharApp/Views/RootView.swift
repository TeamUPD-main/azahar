// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

/// Root navigation view (equivalent to Android's MainActivity).
struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            GameListView()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            appState.showingSettings = true
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            appState.showingDocumentPicker = true
                        } label: {
                            Label("Add Games", systemImage: "plus")
                        }
                    }
                }
                .sheet(isPresented: $appState.showingSettings) {
                    SettingsView()
                }
                .fullScreenCover(isPresented: $appState.isEmulating) {
                    if let game = appState.currentGame {
                        EmulationView(game: game)
                    }
                }
        }
    }
}
