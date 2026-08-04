// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI
import UniformTypeIdentifiers

/// Amiibo file picker using UIDocumentPickerViewController
struct AmiiboFilePicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onAmiiboSelected: (URL) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        
        // Filter to .bin files
        picker.shouldShowFileExtensions = true
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: AmiiboFilePicker
        
        init(_ parent: AmiiboFilePicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            
            // Check if it's a .bin file
            if url.pathExtension.lowercased() == "bin" {
                parent.onAmiiboSelected(url)
            } else {
                AppLogger.error("Amiibo", message: "Selected file is not a .bin file")
            }
            
            parent.isPresented = false
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}
