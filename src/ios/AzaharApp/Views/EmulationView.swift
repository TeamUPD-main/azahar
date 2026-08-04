// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

/// Emulation host view: shows the MetalView, touch overlay, and pause/menu controls.
struct EmulationView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel: EmulationViewModel
    @StateObject private var externalDisplayManager = ExternalDisplayManager.shared
    @State private var showPauseMenu = false
    @State private var showDisplayModeMenu = false
    @State private var isLandscape = UIDevice.current.orientation.isLandscape
    @State private var orientationObserver: NSObjectProtocol?

    let game: Game

    init(game: Game) {
        self.game = game
        _viewModel = StateObject(wrappedValue: EmulationViewModel(game: game))
        
        AppLogger.info("=== EMULATION VIEW INITIALIZED ===")
        AppLogger.gameOperation("EmulationView created", path: game.path, titleId: game.titleId)
    }

    var body: some View {
        ZStack {
            // Main emulation view
            MetalView(viewModel: viewModel)
                .ignoresSafeArea()
                .overlay {
                    // Hide touch controls if external display is in fullscreen mode
                    if !externalDisplayManager.isExternalDisplayConnected || 
                       externalDisplayManager.displayMode != .externalFullscreen {
                        TouchControlsView(viewModel: viewModel)
                    }
                }
            
            // Loading screen overlay
            if viewModel.isLoading {
                EmulationLoadingView(
                    gameTitle: viewModel.gameTitle,
                    gamePath: game.path
                )
                .transition(.opacity)
                .zIndex(100)
            }

            // Top bar overlay (auto-hides)
            VStack {
                HStack {
                    Button {
                        viewModel.togglePause()
                        showPauseMenu = true
                    } label: {
                        Image(systemName: "pause.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    
                    // External display mode button (shown when external display connected)
                    if externalDisplayManager.isExternalDisplayConnected {
                        Button {
                            showDisplayModeMenu = true
                        } label: {
                            Image(systemName: "tv")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                    
                    Spacer()
                    
                    // External display indicator
                    if externalDisplayManager.isExternalDisplayConnected {
                        HStack(spacing: 4) {
                            Image(systemName: "tv.fill")
                                .font(.caption)
                            Text("External")
                                .font(.caption2)
                        }
                        .foregroundStyle(.green)
                        .padding(6)
                        .background(.black.opacity(0.6), in: Capsule())
                    }
                    
                    // Performance stats
                    if viewModel.showPerfStats {
                        Text(viewModel.perfStatsText)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            }
            
            // External display mode selector
            if showDisplayModeMenu {
                ExternalDisplayModeMenu(
                    displayManager: externalDisplayManager,
                    isPresented: $showDisplayModeMenu
                )
            }

            // Pause menu
            if showPauseMenu {
                PauseMenuView(
                    viewModel: viewModel,
                    onResume: {
                        viewModel.resume()
                        showPauseMenu = false
                    },
                    onExit: {
                        viewModel.stop()
                        appState.stopEmulation()
                    }
                )
            }
        }
        .onAppear {
            // Signal MetalView to bind surface and then start
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}

/// Pause menu (equivalent to Android's EmulationMenuDialog).
struct PauseMenuView: View {
    @ObservedObject var viewModel: EmulationViewModel
    let onResume: () -> Void
    let onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onResume() }

            VStack(spacing: 20) {
                Text(gameTitle)
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        PauseButton(title: "Resume", icon: "play.fill", action: onResume)

                        Section("Save/Load State") {
                            HStack(spacing: 8) {
                                ForEach(0..<3) { slot in
                                    Button("Slot \(slot)") {
                                        viewModel.saveState(slot: slot)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            HStack(spacing: 8) {
                                ForEach(0..<3) { slot in
                                    Button("Load \(slot)") {
                                        viewModel.loadState(slot: slot)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }

                        Section("Settings") {
                            Button {
                                viewModel.cycleLayout()
                            } label: {
                                Label("Cycle Layout", systemImage: "rectangle.split.2x2")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                viewModel.toggleTurbo()
                            } label: {
                                Label(
                                    viewModel.turboEnabled ? "Turbo: ON" : "Turbo: OFF",
                                    systemImage: "bolt.fill"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }

                        PauseButton(title: "Exit Game", icon: "xmark.circle.fill", action: onExit)
                            .tint(.red)
                    }
                    .padding(.horizontal)
                }
            }
            .frame(maxWidth: 400)
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
        .transition(.opacity)
    }

    private var gameTitle: String {
        viewModel.gameTitle
    }
}

struct PauseButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
    }
}

/// External Display Mode Selection Menu
struct ExternalDisplayModeMenu: View {
    @ObservedObject var displayManager: ExternalDisplayManager
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }
            
            VStack(spacing: 20) {
                HStack {
                    Image(systemName: "tv")
                        .font(.title2)
                    Text("External Display")
                        .font(.title2.bold())
                    Spacer()
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.white)
                
                VStack(spacing: 12) {
                    ForEach(ExternalDisplayManager.ExternalDisplayMode.allCases, id: \.self) { mode in
                        Button {
                            displayManager.setDisplayMode(mode)
                            isPresented = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mode.displayName)
                                        .font(.subheadline.bold())
                                    Text(mode.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                if displayManager.displayMode == mode {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .foregroundStyle(.white)
                            .padding()
                            .background(
                                displayManager.displayMode == mode ? 
                                    Color.blue.opacity(0.3) : Color.white.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: 500)
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 20)
        }
    }
}
