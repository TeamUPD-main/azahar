// Copyright Citra Emulator Project / Azahar Emulator Project
// Licensed under GPLv2 or any later version
// Refer to the license.txt file included.

import Foundation

/// Represents a game discovered in the user directory.
struct Game: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let title: String
    let titleId: UInt64
    let mediaType: Int32

    var formattedTitleId: String {
        String(format: "%016llX", titleId)
    }
}

/// Scans the user directory for game files.
enum GameScanner {
    private static let supportedExtensions: Set<String> = [
        "3ds", "3dsx", "cxi", "app", "cia", "ncch", "cci", "z3ds", "zcci", "zcxi"
    ]

    static func scan(userDirectory: String) -> [Game] {
        var games: [Game] = []

        // Scan SDMC directory for installed titles
        let sdmcTitles = (userDirectory as NSString).appendingPathComponent(
            "sdmc/Nintendo 3DS/00000000000000000000000000000000/"
            + "00000000000000000000000000000000/title/00040000"
        )
        games.append(contentsOf: scanDirectory(sdmcTitles, mediaType: Int32(AZ_MEDIA_TYPE_SDMC)))

        // Scan NAND directory
        let nandTitles = (userDirectory as NSString).appendingPathComponent(
            "nand/00000000000000000000000000000000/title/00040000"
        )
        games.append(contentsOf: scanDirectory(nandTitles, mediaType: Int32(AZ_MEDIA_TYPE_NAND)))

        // Scan ROMs directory (recursively) - where imported ROMs are stored
        let docsDir = NSSearchPathForDirectoriesInDomains(
            .documentDirectory, .userDomainMask, true
        ).first ?? ""

        let gamesPath = (docsDir as NSString).appendingPathComponent("ROMs")
        games.append(contentsOf: scanDirectory(gamesPath, mediaType: Int32(AZ_MEDIA_TYPE_SDMC)))

        // Deduplicate by path
        var seen = Set<String>()
        return games.filter { seen.insert($0.path).inserted }
    }

    private static func scanDirectory(_ path: String, mediaType: Int32) -> [Game] {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var games: [Game] = []
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }
            let fullPath = fileURL.path
            let titleId = az_get_title_id(fullPath)
            games.append(Game(
                path: fullPath,
                title: fileURL.deletingPathExtension().lastPathComponent,
                titleId: UInt64(bitPattern: titleId),
                mediaType: mediaType
            ))
        }
        return games
    }
}
