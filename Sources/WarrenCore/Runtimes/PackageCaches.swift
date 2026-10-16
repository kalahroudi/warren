// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One shared place for the packages npm, pnpm, Yarn, Bun, Composer, uv and pip download, for processes Warren starts.
/// It only
/// sets
/// the variables each tool already supports. The cache is disposable: clearing it costs a re-download.
public enum PackageCaches {
    public static func environment(_ paths: WarrenPaths) -> [String: String] {
        let root = paths.packagesCacheDirectory
        func folder(_ name: String) -> String {
            root.appendingPathComponent(name, isDirectory: true).path
        }
        return [
            "npm_config_cache": folder("npm"),
            "npm_config_store_dir": folder("pnpm"),
            "YARN_CACHE_FOLDER": folder("yarn"),
            "YARN_ENABLE_GLOBAL_CACHE": "1",
            "YARN_GLOBAL_FOLDER": folder("yarn-berry"),
            "BUN_INSTALL_CACHE_DIR": folder("bun"),
            "COMPOSER_CACHE_DIR": folder("composer"),
            "UV_CACHE_DIR": folder("uv"),
            "PIP_CACHE_DIR": folder("pip"),
        ]
    }

    public static func bytes(_ paths: WarrenPaths) -> Int64 {
        DirectorySize.bytes(of: paths.packagesCacheDirectory)
    }

    public static func clear(_ paths: WarrenPaths) throws {
        let directory = paths.packagesCacheDirectory
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}
