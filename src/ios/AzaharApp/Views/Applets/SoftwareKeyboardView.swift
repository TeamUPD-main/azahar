// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

/// Software keyboard applet (equivalent to Android's KeyboardDialogFragment).
/// Presented as a sheet when the core requests keyboard input.
struct SoftwareKeyboardView: View {
    @Environment(\.dismiss) private var dismiss
    let config: String // JSON config from az_swkbd_get_config
    @State private var inputText = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Enter text...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }

                Spacer()
            }
            .navigationTitle("Keyboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        az_swkbd_cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") {
                        if az_swkbd_submit(inputText, 0) {
                            dismiss()
                        } else {
                            errorMessage = "Invalid input"
                        }
                    }
                }
            }
        }
    }
}
