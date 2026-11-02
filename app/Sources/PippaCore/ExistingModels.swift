import Foundation

/// A place on this Mac that belongs to another program: a search folder or a catalog file found there.
public struct ModelLocation: Sendable, Hashable {
    public var url: URL
    /// Where from, for the UI: "oMLX", "LM Studio" …
    public var source: String
    public init(url: URL, source: String) { self.url = url; self.source = source }
}

/// Finds the catalog model's files that another program already downloaded: oMLX (`~/.omlx/models/<org>/<name>` or
/// `~/.omlx/models/<name>`), LM Studio's MLX folder and the Hugging Face cache. Found only by folder name and file size,
/// without reading anything; adoption happens only after the SHA-256 check (`PiInstaller.adopt`). Foreign files stay untouched.
public enum ExistingModels {
    /// Real user folder; in the sandbox `NSHomeDirectory()` points into the container.
    public static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Known storage locations (programs' default settings).
    public static func defaultRoots(home: URL = realHome) -> [ModelLocation] {
        [(".omlx/models", "oMLX"),
         (".lmstudio/models", "LM Studio"),
         (".cache/huggingface/hub", "Hugging Face")]
            .map { ModelLocation(url: home.appendingPathComponent($0.0, isDirectory: true), source: $0.1) }
    }

    /// Found files by SHA-256 from the catalog model: the real file (symlinks resolved, as in the Hugging Face cache).
    public static func find(_ model: CatalogModel, roots: [ModelLocation] = defaultRoots()) -> [String: ModelLocation] {
        let name = model.repo.split(separator: "/").last.map(String.init) ?? model.key
        let cacheName = "models--" + model.repo.replacingOccurrences(of: "/", with: "--")
        let fm = FileManager.default
        var folders: [(URL, String)] = []
        for root in roots {
            // <root>/<name>, <root>/<org>/<name>, <root>/<key>; Hugging Face: <root>/models--org--name/snapshots/<rev>
            let direct = [root.url.appendingPathComponent(name), root.url.appendingPathComponent(model.repo),
                          root.url.appendingPathComponent(model.key)]
            folders += direct.map { ($0, root.source) }
            let snapshots = root.url.appendingPathComponent(cacheName).appendingPathComponent("snapshots")
            for revision in (try? fm.contentsOfDirectory(at: snapshots, includingPropertiesForKeys: nil)) ?? [] {
                folders.append((revision, root.source))
            }
        }
        var found: [String: ModelLocation] = [:]
        for file in model.pinned?.files ?? [] {
            for (folder, source) in folders where found[file.sha256] == nil {
                let url = folder.appendingPathComponent(file.path).resolvingSymlinksInPath()
                if ModelDownloader.fileSize(url) == file.size { found[file.sha256] = ModelLocation(url: url, source: source) }
            }
        }
        return found
    }
}
