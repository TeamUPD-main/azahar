// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

/// NetPlay lobby browser and room controls (equivalent to Android's LobbyBrowser + NetPlayDialog).
struct NetPlayView: View {
    @State private var publicRooms: [RoomEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var username = UserDefaults.standard.string(forKey: "netplay_username") ?? ""
    @State private var selectedRoom: RoomEntry?

    struct RoomEntry: Identifiable {
        let id = UUID()
        let name: String
        let gameName: String
        let gameId: Int64
        let playerCount: Int
        let maxPlayers: Int
        let hasPassword: Bool
    }

    var body: some View {
        List {
            Section("Settings") {
                TextField("Username", text: $username)
                    .onChange(of: username) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "netplay_username")
                    }
            }

            Section("Public Rooms") {
                if isLoading {
                    ProgressView()
                } else if publicRooms.isEmpty {
                    Text("No rooms available")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(publicRooms) { room in
                        Button {
                            selectedRoom = room
                        } label: {
                            VStack(alignment: .leading) {
                                HStack {
                                    Text(room.name)
                                        .font(.headline)
                                    if room.hasPassword {
                                        Image(systemName: "lock.fill")
                                            .font(.caption)
                                    }
                                    Spacer()
                                    Text("\(room.playerCount)/\(room.maxPlayers)")
                                        .font(.caption)
                                }
                                Text(room.gameName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Button("Refresh") { loadRooms() }
            }
        }
        .navigationTitle("NetPlay")
        .onAppear { loadRooms() }
        .alert("Join Room", isPresented: .constant(selectedRoom != nil)) {
            Button("Join") {
                if selectedRoom != nil {
                    _ = az_netplay_join_room("0.0.0.0", 0, username, "")
                }
                selectedRoom = nil
            }
            Button("Cancel", role: .cancel) { selectedRoom = nil }
        }
    }

    private func loadRooms() {
        isLoading = true
        az_netplay_init()
        let entries = [RoomEntry]()
        // TODO: populate from az_netplay_get_public_rooms
        publicRooms = entries
        isLoading = false
    }
}
