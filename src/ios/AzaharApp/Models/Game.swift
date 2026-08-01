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
    private static let supportedExtensions: Set<String> = ["3ds", "3dsx", "cxi", "app", "cia", "ncch"]

    static func scan(userDirectory: String) -> [Game] {
        var games: [Game] = []

        // Scan SDMC directory for installed titles
        let sdmcTitles = (userDirectory as NSString).appendingPathComponent(
            "sdmc/Nintendo 3DS/00000000000000000000000000000000/"
            + "00000000000000000000000000000000/title/00040000"
        )
        games.append(contentsOf: scanDirectory(sdmcTitles, mediaType: AZ_MEDIA_TYPE_SDMC))

        // Scan NAND directory
        let nandTitles = (userDirectory as NSString).appendingPathComponent(
            "nand/00000000000000000000000000000000/title/00040000"
        )
        games.append(contentsOf: scanDirectory(nandTitles, mediaType: AZ_MEDIA_TYPE_NAND))

        // Scan user-configured directories (add more paths as needed)
        let docsDir = NSSearchPathForDirectoriesInDomains(
            .documentDirectory, .userDomainMask, true
        ).first ?? ""

        let gamesPath = (docsDir as NSString).appendingPathComponent("ROMs")
        if let files = try? FileManager.default.contentsOfDirectory(
            atPath: gamesPath
        ) {
            for file in files where supportedExtensions.contains(
                (file as NSString).pathExtension.lowercased()
            ) {
                let fullPath = (gamesPath as NSString).appendingPathComponent(file)
                let titleId = az_get_title_id(fullPath)
                games.append(Game(
                    path: fullPath,
                    title: (file as NSString).deletingPathExtension,
                    titleId: UInt64(bitPattern: titleId),
                    mediaType: AZ_MEDIA_TYPE_SDMC
                ))
            }
        }

        return games
    }

    private static func scanDirectory(_ path: String, mediaType: Int32) -> [Game] {
        guard let enumerator = FileManager.default.enumerator(
            atPath: path
        ) else { return [] }
        var games: [Game] = []
        while let relative = enumerator.nextObject() as? String {
            let ext = (relative as NSString).pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }
            let fullPath = (path as NSString).appendingPathComponent(relative)
            let titleId = az_get_title_id(fullPath)
            guard titleId != 0 else { continue }
            let name = (relative as NSString).lastPathComponent
            games.append(Game(
                path: fullPath,
                title: (name as NSString).deletingPathExtension,
                titleId: UInt64(bitPattern: titleId),
                mediaType: mediaType
            ))
        }
        return games
    }
}
