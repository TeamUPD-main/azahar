// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

/// Save State slot selector dialog (matches Android's save/load state UI)
struct SaveStateDialog: View {
    @ObservedObject var viewModel: EmulationViewModel
    @Binding var isPresented: Bool
    let isSaving: Bool
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }
            
            VStack(spacing: 20) {
                HStack {
                    Text(isSaving ? "Save State" : "Load State")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                
                Text("Select a slot")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(0..<6) { slot in
                        SaveStateSlotButton(
                            slot: slot,
                            isSaving: isSaving,
                            exists: viewModel.saveStateExists(slot: slot),
                            timestamp: viewModel.saveStateTimestamp(slot: slot)
                        ) {
                            if isSaving {
                                viewModel.saveState(slot: slot)
                            } else {
                                viewModel.loadState(slot: slot)
                            }
                            isPresented = false
                        }
                    }
                }
                
                if !isSaving {
                    Text("Tap a slot to load")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(24)
            .frame(maxWidth: 400)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)
        }
    }
}

struct SaveStateSlotButton: View {
    let slot: Int
    let isSaving: Bool
    let exists: Bool
    let timestamp: String?
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: exists ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(exists ? .green : .gray)
                    Spacer()
                }
                
                Text("Slot \(slot)")
                    .font(.headline)
                    .foregroundStyle(.white)
                
                if let timestamp = timestamp {
                    Text(timestamp)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                } else {
                    Text(isSaving ? "Empty" : "No save")
                        .font(.caption2)
                        .foregroundStyle(.gray)
                }
                
                Image(systemName: isSaving ? "square.and.arrow.down" : "square.and.arrow.up")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                exists ? Color.blue.opacity(0.2) : Color.white.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .disabled(!isSaving && !exists)
    }
}
