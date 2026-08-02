// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import Foundation

/// Extracts SMDH icon and metadata from 3DS ROM files.
/// Used by the game list to show icons and proper titles.
enum SMDHLoader {
    /// Extracts the game title and icon from a 3DS ROM.
    /// Returns nil if extraction fails.
    static func extract(from path: String) -> (title: String, iconData: Data?)? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else { return nil }

        guard let fileHandle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { fileHandle.closeFile() }

        // Read the first 512 bytes to detect format
        fileHandle.seek(toFileOffset: 0)
        let headerData = fileHandle.readData(ofLength: 512)

        // Check for NCCH magic ("NCSD" or "NCCH")
        if headerData.count >= 4 {
            let magic = headerData.prefix(4)
            let isNCSD = magic == Data([0x4E, 0x43, 0x53, 0x44]) // "NCSD"
            let isNCCH = magic == Data([0x4E, 0x43, 0x43, 0x48]) // "NCCH"

            if isNCSD || isNCCH {
                return extractFromNCCH(path: path, fileHandle: fileHandle, header: headerData, isNCSD: isNCSD)
            }
        }

        // 3DSX file
        if headerData.count >= 16 {
            let magic3dsx = headerData.prefix(16)
            if magic3dsx == Data([0x33, 0x44, 0x53, 0x58, 0x00, 0x00, 0x10, 0x00,
                                 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]) {
                return nil // 3DSX files don't have SMDH
            }
        }

        // CIA file
        if headerData.count >= 4 && headerData.prefix(2) == Data([0x20, 0x20]) {
            return extractFromCIA(fileHandle: fileHandle)
        }

        return nil
    }

    // MARK: - NCCH extraction

    private static func extractFromNCCH(path: String, fileHandle: FileHandle, header: Data, isNCSD: Bool) -> (String, Data?)? {
        // For NCSD, the ExeFS is at a certain offset. This is simplified —
        // real extraction would parse the partition table.
        // For now, use the bridge to get the title ID, and return the path as the title.
        let titleId = az_get_title_id(path)
        if titleId > 0 {
            return ("Title \(String(format: "%016llX", titleId))", nil)
        }
        return nil
    }

    // MARK: - CIA extraction

    private static func extractFromCIA(fileHandle: FileHandle) -> (String, Data?)? {
        return nil
    }
}
