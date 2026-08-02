// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

/// RetroAchievements login and status view
struct RetroAchievementsView: View {
    @State private var username = ""
    @State private var password = ""
    @State private var isLoggedIn = false
    @State private var isEnabled = false
    @State private var userInfo: RetroAchievementsUser?
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isLoggingIn = false
    
    var body: some View {
        List {
            Section("Status") {
                Toggle("Enable RetroAchievements", isOn: $isEnabled)
                    .onChange(of: isEnabled) { _, newValue in
                        az_ra_set_enabled(newValue)
                    }
                
                if isEnabled {
                    HStack {
                        Label("Account", systemImage: "person.circle")
                        Spacer()
                        Text(isLoggedIn ? "Logged In" : "Not Logged In")
                            .foregroundStyle(isLoggedIn ? .green : .secondary)
                    }
                    
                    if let user = userInfo {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Username:")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(user.username)
                            }
                            
                            HStack {
                                Text("Score:")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(user.score) points")
                            }
                        }
                        .font(.caption)
                    }
                }
            }
            
            if isEnabled && !isLoggedIn {
                Section("Login") {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                    
                    Button {
                        loginToRetroAchievements()
                    } label: {
                        if isLoggingIn {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                Text("Logging in...")
                            }
                        } else {
                            Label("Login", systemImage: "arrow.right.circle")
                        }
                    }
                    .disabled(username.isEmpty || password.isEmpty || isLoggingIn)
                    
                    Text("Create a free account at retroachievements.org to track your achievements across all your games.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if isEnabled && isLoggedIn {
                Section("Account") {
                    Button(role: .destructive) {
                        logoutFromRetroAchievements()
                    } label: {
                        Label("Logout", systemImage: "arrow.left.circle")
                    }
                }
            }
            
            Section("About") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("RetroAchievements")
                        .font(.headline)
                    
                    Text("Track your achievements, compete on leaderboards, and earn points across all your favorite 3DS games. RetroAchievements is a community-driven achievement system.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Link("Visit RetroAchievements.org", destination: URL(string: "https://retroachievements.org")!)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("RetroAchievements")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadStatus()
        }
        .alert("RetroAchievements", isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }
    
    private func loadStatus() {
        isEnabled = az_ra_is_enabled()
        isLoggedIn = az_ra_is_logged_in()
        
        if isLoggedIn {
            loadUserInfo()
        }
    }
    
    private func loadUserInfo() {
        guard let userPtr = az_ra_get_user() else { return }
        
        let user = userPtr.pointee
        userInfo = RetroAchievementsUser(
            username: String(cString: user.username),
            displayName: String(cString: user.display_name),
            score: Int(user.score),
            scoreSoftcore: Int(user.score_softcore),
            token: String(cString: user.token),
            avatarUrl: String(cString: user.avatar_url)
        )
    }
    
    private func loginToRetroAchievements() {
        isLoggingIn = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            az_ra_login(username, password)
            
            // Wait a bit for login to complete
            Thread.sleep(forTimeInterval: 2.0)
            
            DispatchQueue.main.async {
                isLoggingIn = false
                
                if az_ra_is_logged_in() {
                    isLoggedIn = true
                    loadUserInfo()
                    alertMessage = "Successfully logged in to RetroAchievements!"
                    
                    // Clear password
                    password = ""
                } else {
                    alertMessage = "Login failed. Please check your credentials and try again."
                }
                showingAlert = true
            }
        }
    }
    
    private func logoutFromRetroAchievements() {
        az_ra_logout()
        isLoggedIn = false
        userInfo = nil
        username = ""
        password = ""
        
        alertMessage = "Logged out successfully."
        showingAlert = true
    }
}

struct RetroAchievementsUser {
    let username: String
    let displayName: String
    let score: Int
    let scoreSoftcore: Int
    let token: String
    let avatarUrl: String
}
