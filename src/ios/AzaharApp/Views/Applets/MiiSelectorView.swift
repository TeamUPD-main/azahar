// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

/// Mii selector applet (equivalent to Android's MiiSelectorDialogFragment).
/// Displays available Miis for the user to choose from.
struct MiiSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMii: Int?

    var body: some View {
        NavigationStack {
            List(0..<6, id: \.self) { index in
                Button {
                    selectedMii = index
                } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray5))
                            .frame(width: 48, height: 48)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(.secondary)
                            }
                        Text("Mii \(index)")
                        Spacer()
                        if selectedMii == index {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Select Mii")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        az_mii_cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") {
                        if let idx = selectedMii {
                            _ = az_mii_select(Int32(idx))
                        }
                        dismiss()
                    }
                    .disabled(selectedMii == nil)
                }
            }
        }
    }
}
