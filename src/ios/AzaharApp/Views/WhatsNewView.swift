// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import SwiftUI

struct WhatsNewView: View {
    let entry: WhatsNewEntry
    let onDismiss: () -> Void
    
    @State private var offset: CGFloat = 0
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with app icon
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 120, height: 120)
                            
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.white)
                        }
                        .shadow(color: .blue.opacity(0.3), radius: 20, x: 0, y: 10)
                        
                        VStack(spacing: 8) {
                            Text("What's New in Azahar")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            
                            Text("Version \(entry.version)")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            
                            if let date = formatDate(entry.releaseDate) {
                                Text(date)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .padding(.top, 20)
                    
                    // Changelog sections
                    VStack(spacing: 16) {
                        ForEach(entry.sections, id: \.title) { section in
                            sectionCard(section)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Compatibility info
                    if let compatibility = entry.compatibility {
                        compatibilityCard(compatibility)
                            .padding(.horizontal)
                    }
                    
                    // Notes
                    if let notes = entry.notes, !notes.isEmpty {
                        notesCard(notes)
                            .padding(.horizontal)
                    }
                    
                    // Continue button
                    Button {
                        onDismiss()
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }
    
    // MARK: - Section Card
    
    private func sectionCard(_ section: WhatsNewEntry.ChangelogSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                sectionIcon(for: section.title)
                    .font(.title2)
                
                Text(section.title)
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(sectionColor(for: section.title))
            
            Divider()
            
            // Items
            VStack(alignment: .leading, spacing: 8) {
                ForEach(section.items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .fontWeight(.bold)
                            .foregroundStyle(sectionColor(for: section.title))
                        
                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding()
        .background(Material.thin)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Compatibility Card
    
    private func compatibilityCard(_ compatibility: WhatsNewEntry.CompatibilityInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                
                Text("Compatibility")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            
            Divider()
            
            VStack(spacing: 8) {
                compatibilityRow(
                    icon: "iphone",
                    title: "Minimum iOS",
                    value: compatibility.minimumIOSVersion
                )
                
                compatibilityRow(
                    icon: "star.fill",
                    title: "Recommended iOS",
                    value: compatibility.recommendedIOSVersion
                )
                
                if compatibility.requiresStikDebug {
                    compatibilityRow(
                        icon: "app.badge.checkmark",
                        title: "Requires",
                        value: "StikDebug"
                    )
                }
                
                if compatibility.requiresLocalDevVPN {
                    compatibilityRow(
                        icon: "network",
                        title: "Requires",
                        value: "LocalDevVPN"
                    )
                }
            }
        }
        .padding()
        .background(Material.thin)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private func compatibilityRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
    
    // MARK: - Notes Card
    
    private func notesCard(_ notes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                
                Text("Important Notes")
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(notes, id: \.self) { note in
                    HStack(alignment: .top, spacing: 8) {
                        Text("ℹ︎")
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
                        
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding()
        .background(Material.thin)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Helpers
    
    private func sectionIcon(for title: String) -> Image {
        let iconName: String
        switch title.lowercased() {
        case let t where t.contains("feature"):
            iconName = "star.fill"
        case let t where t.contains("improvement"):
            iconName = "arrow.up.circle.fill"
        case let t where t.contains("technical"):
            iconName = "gearshape.fill"
        case let t where t.contains("fix"), let t where t.contains("bug"):
            iconName = "wrench.and.screwdriver.fill"
        default:
            iconName = "circle.fill"
        }
        return Image(systemName: iconName)
    }
    
    private func sectionColor(for title: String) -> Color {
        switch title.lowercased() {
        case let t where t.contains("feature"):
            return .green
        case let t where t.contains("improvement"):
            return .blue
        case let t where t.contains("technical"):
            return .purple
        case let t where t.contains("fix"), let t where t.contains("bug"):
            return .orange
        default:
            return .gray
        }
    }
    
    private func formatDate(_ dateString: String) -> String? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        
        guard let date = formatter.date(from: dateString) else {
            return nil
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        return displayFormatter.string(from: date)
    }
}

// MARK: - Preview

#Preview {
    WhatsNewView(
        entry: WhatsNewEntry(
            version: "1.0.0",
            releaseDate: "2026-08-03",
            sections: [
                WhatsNewEntry.ChangelogSection(
                    title: "New Features",
                    items: [
                        "StikDebug JIT integration",
                        "RetroAchievements support",
                        "Auto-enable JIT on launch"
                    ]
                ),
                WhatsNewEntry.ChangelogSection(
                    title: "Bug Fixes",
                    items: [
                        "Fixed compilation warnings",
                        "Improved stability"
                    ]
                )
            ],
            compatibility: WhatsNewEntry.CompatibilityInfo(
                minimumIOSVersion: "17.4",
                recommendedIOSVersion: "26.0",
                requiresStikDebug: true,
                requiresLocalDevVPN: true
            ),
            notes: [
                "JIT is recommended for smooth gameplay",
                "Install StikDebug from GitHub"
            ]
        ),
        onDismiss: {}
    )
}
