// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

/// Per-game settings configuration
struct PerGameSettingsView: View {
    let game: Game
    @State private var cpuClockPercentage: Double = 100.0
    @State private var useCustomCpuClock = false
    @State private var resolutionFactor: Int = 1
    @State private var useDiskShaderCache = true
    @State private var useAsyncShaderCompilation = true
    @State private var useHardwareShader = true
    @State private var accurateMultiplication = false
    @State private var use3dMode: Int = 0 // 0=Off, 1=Side-by-side, 2=Anaglyph
    @State private var factor3d: Int = 0
    
    var body: some View {
        List {
            Section {
                Toggle("Use Custom CPU Clock", isOn: $useCustomCpuClock)
                
                if useCustomCpuClock {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("CPU Clock Speed")
                            Spacer()
                            Text("\(Int(cpuClockPercentage))%")
                                .foregroundStyle(.secondary)
                                .fontDesign(.monospaced)
                        }
                        
                        Slider(value: $cpuClockPercentage, in: 5...400, step: 5)
                        
                        HStack {
                            Text("5%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("100%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("400%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("CPU Emulation")
            } footer: {
                if useCustomCpuClock {
                    Text("Adjust CPU clock speed for this game. Lower values may improve performance on slower devices. Higher values may fix timing-sensitive games. Default is 100%.")
                } else {
                    Text("Use the global CPU clock setting for this game.")
                }
            }
            
            Section {
                Picker("Internal Resolution", selection: $resolutionFactor) {
                    Text("1x Native (400×240)").tag(1)
                    Text("2x Native (800×480)").tag(2)
                    Text("3x Native (1200×720)").tag(3)
                    Text("4x Native (1600×960)").tag(4)
                    Text("5x Native (2000×1200)").tag(5)
                    Text("6x Native (2400×1440)").tag(6)
                    Text("7x Native (2800×1680)").tag(7)
                    Text("8x Native (3200×1920)").tag(8)
                    Text("9x Native (3600×2160)").tag(9)
                    Text("10x Native (4000×2400)").tag(10)
                }
                
                Toggle("Use Hardware Shader", isOn: $useHardwareShader)
                Toggle("Accurate Multiplication", isOn: $accurateMultiplication)
                Toggle("Use Disk Shader Cache", isOn: $useDiskShaderCache)
                Toggle("Async Shader Compilation", isOn: $useAsyncShaderCompilation)
            } header: {
                Text("Graphics")
            } footer: {
                Text("Higher internal resolutions improve image quality but may reduce performance. Hardware shaders are faster but may have compatibility issues. Disk shader cache reduces stuttering.")
            }
            
            Section {
                Picker("Stereoscopic 3D Mode", selection: $use3dMode) {
                    Text("Off").tag(0)
                    Text("Side by Side").tag(1)
                    Text("Anaglyph (Red-Cyan)").tag(2)
                    Text("Interlaced").tag(3)
                    Text("Reverse Interlaced").tag(4)
                }
                
                if use3dMode > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("3D Depth")
                            Spacer()
                            Text("\(factor3d)%")
                                .foregroundStyle(.secondary)
                                .fontDesign(.monospaced)
                        }
                        
                        Slider(value: Binding(
                            get: { Double(factor3d) },
                            set: { factor3d = Int($0) }
                        ), in: 0...100, step: 5)
                    }
                }
            } header: {
                Text("Stereoscopic 3D")
            } footer: {
                Text("Enable stereoscopic 3D effect. Side-by-side mode works with VR headsets. Anaglyph mode requires red-cyan glasses.")
            }
            
            Section {
                Button {
                    applySettings()
                } label: {
                    HStack {
                        Spacer()
                        Text("Apply Settings")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button(role: .destructive) {
                    resetToDefaults()
                } label: {
                    HStack {
                        Spacer()
                        Text("Reset to Defaults")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Game Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadPerGameSettings()
        }
    }
    
    private func loadPerGameSettings() {
        // Load per-game settings for this title ID
        let titleIdStr = game.formattedTitleId
        
        // CPU Clock
        let customClock = az_setting_get_bool("Game-\(titleIdStr)", "use_custom_cpu_ticks", false)
        useCustomCpuClock = customClock
        if customClock {
            let clockPercent = az_setting_get_int("Game-\(titleIdStr)", "cpu_clock_percentage", 100)
            cpuClockPercentage = Double(clockPercent)
        }
        
        // Graphics
        resolutionFactor = Int(az_setting_get_int("Game-\(titleIdStr)", "resolution_factor", 1))
        useHardwareShader = az_setting_get_bool("Game-\(titleIdStr)", "use_hw_shader", true)
        accurateMultiplication = az_setting_get_bool("Game-\(titleIdStr)", "shaders_accurate_mul", false)
        useDiskShaderCache = az_setting_get_bool("Game-\(titleIdStr)", "use_disk_shader_cache", true)
        useAsyncShaderCompilation = az_setting_get_bool("Game-\(titleIdStr)", "async_shader_compilation", true)
        
        // 3D
        use3dMode = Int(az_setting_get_int("Game-\(titleIdStr)", "render_3d", 0))
        factor3d = Int(az_setting_get_int("Game-\(titleIdStr)", "factor_3d", 0))
    }
    
    private func applySettings() {
        let titleIdStr = game.formattedTitleId
        
        // CPU Clock
        az_setting_set_bool("Game-\(titleIdStr)", "use_custom_cpu_ticks", useCustomCpuClock)
        if useCustomCpuClock {
            az_setting_set_int("Game-\(titleIdStr)", "cpu_clock_percentage", Int(cpuClockPercentage))
        }
        
        // Graphics
        az_setting_set_int("Game-\(titleIdStr)", "resolution_factor", resolutionFactor)
        az_setting_set_bool("Game-\(titleIdStr)", "use_hw_shader", useHardwareShader)
        az_setting_set_bool("Game-\(titleIdStr)", "shaders_accurate_mul", accurateMultiplication)
        az_setting_set_bool("Game-\(titleIdStr)", "use_disk_shader_cache", useDiskShaderCache)
        az_setting_set_bool("Game-\(titleIdStr)", "async_shader_compilation", useAsyncShaderCompilation)
        
        // 3D
        az_setting_set_int("Game-\(titleIdStr)", "render_3d", use3dMode)
        az_setting_set_int("Game-\(titleIdStr)", "factor_3d", factor3d)
        
        // Reload settings to apply changes
        az_reload_settings()
    }
    
    private func resetToDefaults() {
        useCustomCpuClock = false
        cpuClockPercentage = 100.0
        resolutionFactor = 1
        useHardwareShader = true
        accurateMultiplication = false
        useDiskShaderCache = true
        useAsyncShaderCompilation = true
        use3dMode = 0
        factor3d = 0
        
        // Clear saved settings
        let titleIdStr = game.formattedTitleId
        az_setting_set_bool("Game-\(titleIdStr)", "use_custom_cpu_ticks", false)
    }
}

/// Cheat management view for a specific game
struct CheatManagementView: View {
    let game: Game
    @State private var cheats: [CheatEntry] = []
    @State private var isLoading = true
    @State private var showError = false
    @State private var errorMessage = ""
    
    struct CheatEntry: Identifiable {
        let id: Int64
        var name: String
        var enabled: Bool
    }
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading cheats...")
            } else if cheats.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    
                    Text("No cheats available")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    Text("Place cheat files in the cheats directory")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } else {
                List {
                    ForEach($cheats) { $cheat in
                        Toggle(isOn: $cheat.enabled) {
                            Text(cheat.name)
                                .font(.subheadline)
                        }
                        .onChange(of: cheat.enabled) { oldValue, newValue in
                            toggleCheat(cheat.id, enabled: newValue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Cheats")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Apply") {
                    applyAllCheats()
                }
                .disabled(cheats.isEmpty)
            }
        }
        .onAppear {
            loadCheats()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func loadCheats() {
        isLoading = true
        
        // Get cheats directory path
        let documentsPath = NSSearchPathForDirectoriesInDomains(
            .documentDirectory, .userDomainMask, true
        ).first ?? ""
        let cheatsPath = (documentsPath as NSString).appendingPathComponent("cheats")
        let cheatFile = (cheatsPath as NSString).appendingPathComponent("\(game.formattedTitleId).txt")
        
        // Check if cheat file exists
        guard FileManager.default.fileExists(atPath: cheatFile) else {
            isLoading = false
            return
        }
        
        // Load cheats via bridge
        var cheatEntries = [az_cheat_entry](repeating: az_cheat_entry(), count: 100)
        let count = az_cheats_load(cheatFile, &cheatEntries, 100)
        
        guard count > 0 else {
            isLoading = false
            return
        }
        
        cheats = (0..<Int(count)).map { i in
            let entry = cheatEntries[i]
            return CheatEntry(
                id: entry.id,
                name: String(cString: entry.name),
                enabled: entry.enabled
            )
        }
        
        isLoading = false
    }
    
    private func toggleCheat(_ cheatId: Int64, enabled: Bool) {
        let success = az_cheats_set_enabled(cheatId, enabled)
        if !success {
            errorMessage = "Failed to toggle cheat"
            showError = true
        }
    }
    
    private func applyAllCheats() {
        let success = az_cheats_apply()
        if !success {
            errorMessage = "Failed to apply cheats. Make sure emulation is running."
            showError = true
        }
    }
}

#Preview {
    NavigationStack {
        PerGameSettingsView(
            game: Game(
                path: "/path/to/game.3ds",
                title: "The Legend of Zelda: Ocarina of Time 3D",
                titleId: 0x0004000000033500,
                mediaType: 0,
                publisher: "Nintendo",
                playTimeSeconds: 3723,
                iconImage: nil
            )
        )
    }
}
