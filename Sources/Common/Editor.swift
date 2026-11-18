import Foundation

/// Where the config file is: `$WM_CONFIG`, else `$XDG_CONFIG_HOME/wm/init.lua`, else `~/.config/wm/init.lua`.
/// The daemon and `wm lsp` both ask this, so they always agree.
public func defaultConfigURL(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    home: URL = FileManager.default.homeDirectoryForCurrentUser
) -> URL {
    if let path = environment["WM_CONFIG"], !path.isEmpty {
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }
    let base = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        ?? home.appendingPathComponent(".config")
    return base.appendingPathComponent("wm/init.lua")
}

/// The `.luarc.json` that makes lua-language-server read the `wm` type stubs in `typesPath`: completion, hover help and
/// warnings for `init.lua` in any editor that runs the server.
public func luarcJSON(typesPath: String) -> String {
    let settings: [String: Any] = [
        "runtime.version": "Lua 5.4",
        "workspace.library": [typesPath],
        "diagnostics.neededFileStatus": ["undefined-field": "Any", "missing-fields": "Any"],
    ]
    let data = (try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
    // JSONSerialization writes `"key" : value`; the usual style is `"key": value`.
    return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\" : ", with: "\": ") + "\n"
}

/// The `.taplo.toml` that makes Taplo (the TOML language server, in the "Even Better TOML" extension) complete and check
/// `shortcuts.toml` with the schema at `schemaURL`.
public func taploConfig(schemaURL: String) -> String {
    """
    # Made by `wm lsp --write`: completion and checks for shortcuts.toml.
    [[rule]]
    include = ["shortcuts.toml"]

    [rule.schema]
    path = "\(schemaURL)"

    """
}
