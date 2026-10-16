// SPDX-License-Identifier: Apache-2.0

import Foundation

public extension WarrenPaths {
    /// The files of a site's running pieces, all in the run folder.
    func phpSocket(_ siteID: String) -> URL {
        runDirectory.appendingPathComponent("php-\(siteID).sock")
    }

    func phpConfig(_ siteID: String) -> URL {
        runDirectory.appendingPathComponent("php-\(siteID).conf")
    }

    /// Present while a static site is switched on.
    func staticMarker(_ siteID: String) -> URL {
        runDirectory.appendingPathComponent("static-\(siteID).on")
    }

    func siteLog(_ siteID: String) -> URL {
        logsDirectory.appendingPathComponent("site-\(siteID).log")
    }
}

public enum NotServed: Error, Equatable, Sendable {
    case noPort
    case notStarted

    public var text: String {
        switch self {
        case .noPort: "no run.port in .warren.toml"
        case .notStarted: "not started"
        }
    }
}

/// What the proxy does for a site, decided from the project's files and Warren's run folder. It never asks launchd,
/// so building the proxy configuration stays cheap.
public enum SiteServing {
    public static func target(for site: ResolvedSite, paths: WarrenPaths) -> Result<ProxyTarget, NotServed> {
        if let port = site.port {
            return .success(.server(port: port))
        }
        let detection = FrameworkDetector.detect(site: site)
        let folder = URL(fileURLWithPath: site.path, isDirectory: true)
        switch detection.kind {
        case .php:
            guard JobHost(paths: paths).hasPlist(stem: "php-\(site.id)") else { return .failure(.notStarted) }
            return .success(.php(socket: paths.phpSocket(site.id).path, root: root(folder, detection)))
        case .staticFiles:
            guard FileManager.default.fileExists(atPath: paths.staticMarker(site.id).path) else {
                return .failure(.notStarted)
            }
            return .success(.staticFiles(root: root(folder, detection)))
        case .server:
            guard let port = SitePorts(paths: paths).assigned(for: site.id) else { return .failure(.notStarted) }
            return .success(.server(port: port))
        case .unknown:
            return .failure(.noPort)
        }
    }

    /// The folder PHP and static files are served from.
    public static func root(_ folder: URL, _ detection: FrameworkDetection) -> String {
        let relative = detection.documentRoot ?? "."
        return (relative == "." ? folder : folder.appendingPathComponent(relative, isDirectory: true))
            .standardizedFileURL.path
    }
}
