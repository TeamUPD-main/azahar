// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI
import UniformTypeIdentifiers

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

/// Document picker for importing ROMs
struct DocumentPicker: UIViewControllerRepresentable {
    let onComplete: ([URL]) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let supportedTypes: [UTType] = [
            UTType(filenameExtension: "3ds") ?? .data,
            UTType(filenameExtension: "cci") ?? .data,
            UTType(filenameExtension: "cxi") ?? .data,
            UTType(filenameExtension: "3dsx") ?? .data,
            UTType(filenameExtension: "cia") ?? .data,
            UTType(filenameExtension: "z3ds") ?? .data,
            UTType(filenameExtension: "zcci") ?? .data,
            UTType(filenameExtension: "zcxi") ?? .data,
            UTType(filenameExtension: "z3dsx") ?? .data,
            UTType(filenameExtension: "zcia") ?? .data,
            UTType(filenameExtension: "elf") ?? .data,
            UTType(filenameExtension: "axf") ?? .data,
        ]
        
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onComplete: ([URL]) -> Void
        
        init(onComplete: @escaping ([URL]) -> Void) {
            self.onComplete = onComplete
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onComplete(urls)
        }
    }
}
