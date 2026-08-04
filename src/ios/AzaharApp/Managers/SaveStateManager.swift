// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import Foundation

/// Save state timestamp and metadata management
class SaveStateManager {
    static let shared = SaveStateManager()
    
    private init() {}
    
    /// Get the timestamp for a save state slot
    func getTimestamp(for titleId: UInt64, slot: Int) -> Date? {
        let userDir = FileUtil.GetUserPath(FileUtil.UserPath.StatesDir)
        let filename = String(format: "%016llX.%02d.cst", titleId, slot)
        let path = (userDir as NSString).appendingPathComponent(filename)
        
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            return attributes[.modificationDate] as? Date
        } catch {
            AppLogger.error("SaveState", message: "Failed to get timestamp for slot \(slot): \(error)")
            return nil
        }
    }
    
    /// Check if a save state exists for the given title and slot
    func exists(for titleId: UInt64, slot: Int) -> Bool {
        return getTimestamp(for: titleId, slot: slot) != nil
    }
    
    /// Format timestamp for display
    func formatTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// Helper for FileUtil bridge
private enum FileUtil {
    enum UserPath {
        case StatesDir
    }
    
    static func GetUserPath(_ path: UserPath) -> String {
        let userDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""
        return (userDir as NSString).appendingPathComponent("states")
    }
}
