import Foundation

public enum CompletionShell: String, CaseIterable, Sendable {
    case zsh
    case bash
}

public struct CompletionCandidate: Equatable, Sendable {
    public var word: String
    public var summary: String?

    public init(_ word: String, _ summary: String? = nil) {
        self.word = word
        self.summary = summary
    }
}

public enum CompletionResult: Equatable, Sendable {
    case candidates([CompletionCandidate])
    case command
    case file
}

public struct LiveWindow: Equatable, Sendable {
    public var id: UInt32
    public var app: String
    public var title: String

    public init(id: UInt32, app: String, title: String) {
        self.id = id
        self.app = app
        self.title = title
    }
}

public struct CompletionSource {
    public var windows: () -> [LiveWindow] = { [] }
    public var workspaces: () -> [String] = { [] }
    public var modes: () -> [String] = { [] }
    public var marks: () -> [String] = { [] }

    public init() {}
}

private enum LiveArgument { case window, workspace, special, mode, mark }

private let liveArguments: [String: LiveArgument] = [
    "focus window": .window,
    "workspace": .workspace,
    "window send workspace": .workspace,
    "workspace special": .special,
    "mode": .mode,
    "focus mark": .mark,
    "window unmark": .mark,
]

private struct CompletionNode {
    var children: [(word: String, summary: String?)] = []
    var values: [String] = []
    var flags: [String] = []
}

private let monitorWords = ["left", "right", "up", "down", "next", "prev", "last", "main", "secondary", "tertiary"]

private let extraValues: [String: [String]] = [
    "list": ["windows", "workspaces", "monitors", "keyboards", "memory", "binds"],
    "query": ["windows", "workspaces", "monitors", "keyboards", "memory"],
    "zen": ["on", "off"],
    "layout set": ["scrolling", "tiling", "master", "monocle", "floating"],
    "init": ["omarchy", "osx", "windows", "i3", "hyprland", "niri"],
    "resize": ["width", "height", "smart", "left", "right", "up", "down"],
    "window place": ["2", "3", "4", "5", "6", "2+1", "1+2", "2/3", "3/4", "1/4", "center"],
    "workspace float-all": ["on", "off", "2", "3", "4", "5", "6", "2+1", "1+2", "2/3", "3/4", "1/4"],
    "window pip": ["on", "off", "toggle"],
    "window snap": ["left", "right", "top", "bottom", "top-left", "top-right", "bottom-left", "bottom-right", "top-center", "bottom-center", "center"],
    "workspace": ["next", "prev", "empty"],
    "workspaces": ["balance"],
    "animations": ["on", "off", "windows", "workspaces", "special", "overlays"],
    "workspace all": ["scrolling", "tiling", "master", "monocle", "floating"],
    "window send workspace": ["next", "prev", "empty"],
    "focus monitor": monitorWords,
    "window send monitor": monitorWords,
    "workspace move monitor": monitorWords,
    "layout tile": ["2", "3", "4", "5", "6", "2+1", "1+2", "2/3", "3/4", "1/4", "center"],
]

private let extraFlags: [String: [String]] = [
    "exec": ["--float", "--tile", "--center", "--maximize", "--focus", "--no-focus", "--workspace", "--monitor", "--width", "--size", "--layout", "--timeout", "--app"],
]

/// A word that only starts subcommands (`wm window ...`) has no command of its own, so no summary in `commandSpecs`.
private let groupSummaries: [String: String] = [
    "window": "Act on a window: close, float, move, send, snap, place.",
    "workspaces": "Act on all workspaces at once (balance).",
    "layout": "Change the layout of the workspace and its columns, stacks and splits.",
    "menubar": "Set or reset the text of the menu bar icon.",
    "key": "Send a key to an app, or type one.",
    "memory": "Manage what `window remember` keeps.",
    "session": "Save the windows and layouts under a name, and open them again.",
    "daemon": "Start, stop, check or reload the wm daemon.",
    "config": "Check the config without applying it.",
]

private let directionNames = ["left", "right", "up", "down"]
private let placeholders: Set<String> = ["name", "pattern", "fraction", "n"]
private let globalFlags = ["--window", "--json", "--verbose", "--help"]

private func literalValues(of args: String) -> [String] {
    guard let first = args.split(separator: " ").first else { return [] }
    let inner = first.trimmingCharacters(in: CharacterSet(charactersIn: "<>[]"))
    if inner == "dir" { return directionNames }
    let alternatives = inner.split(separator: "|").map(String.init)
    guard alternatives.count > 1 else { return [] }
    return alternatives.flatMap { word -> [String] in
        if word == "dir" { return directionNames }
        let isWord = word.first?.isLowercase == true && word.allSatisfy { $0.isLowercase || $0 == "-" }
        return isWord && !placeholders.contains(word) ? [word] : []
    }
}

private func options(of flags: String) -> [String] {
    flags.split(whereSeparator: { " []".contains($0) }).compactMap { part in
        guard part.hasPrefix("--") else { return nil }
        return String(part.prefix { $0 != "=" })
    }
}

private func completionNodes() -> [(path: String, node: CompletionNode)] {
    var order: [String] = []
    var nodes: [String: CompletionNode] = [:]
    func edit(_ path: [String], _ change: (inout CompletionNode) -> Void) {
        let key = path.joined(separator: " ")
        if nodes[key] == nil { order.append(key) }
        change(&nodes[key, default: CompletionNode()])
    }
    for spec in commandSpecs {
        let words = spec.words
        for depth in 0..<words.count {
            let isLeaf = depth == words.count - 1
            edit(Array(words.prefix(depth))) { node in
                if let index = node.children.firstIndex(where: { $0.word == words[depth] }) {
                    if isLeaf { node.children[index].summary = spec.summary }
                } else {
                    node.children.append((words[depth], isLeaf ? spec.summary : groupSummaries[words[depth]]))
                }
            }
        }
        edit(words) { node in
            for value in literalValues(of: spec.args) + (extraValues[spec.path] ?? []) where !node.values.contains(value) {
                node.values.append(value)
            }
            node.flags += options(of: spec.flags) + (extraFlags[spec.path] ?? [])
        }
    }
    return order.map { ($0, nodes[$0]!) }
}

public func complete(_ words: [String], source: CompletionSource = CompletionSource()) -> CompletionResult {
    let nodes = Dictionary(uniqueKeysWithValues: completionNodes().map { ($0.path, $0.node) })
    var path = ""
    var positionals = 0
    var skipNext = false
    for word in words.dropLast() {
        if skipNext { skipNext = false; continue }
        if word == "--window" { skipNext = true; continue }
        if word.hasPrefix("-") { continue }
        if positionals == 0, nodes[path]?.children.contains(where: { $0.word == word }) == true {
            path += (path.isEmpty ? "" : " ") + word
        } else {
            positionals += 1
        }
    }
    let current = words.last ?? ""
    let node = nodes[path] ?? CompletionNode()

    if words.dropLast().last == "--window" {
        let windows = source.windows()
        let apps = Set(windows.map(\.app)).sorted().map { CompletionCandidate("app:" + $0) }
        return .candidates([CompletionCandidate("focused")] + windowCandidates(windows) + apps)
    }
    if current.hasPrefix("-") {
        return .candidates((node.flags + globalFlags.filter { !node.flags.contains($0) }).map { CompletionCandidate($0) })
    }
    if path == "exec" { return positionals == 0 ? .command : .file }
    guard positionals == 0 else { return .candidates([]) }

    var found = node.children.map { CompletionCandidate($0.word, $0.summary) } + node.values.map { CompletionCandidate($0) }
    switch liveArguments[path] {
    case .window?: found += windowCandidates(source.windows())
    case .workspace?: found += source.workspaces().filter { !$0.hasPrefix("special") }.map { CompletionCandidate($0) }
    case .special?: found += source.workspaces().filter { $0.hasPrefix("special:") }.map { CompletionCandidate(String($0.dropFirst("special:".count))) }
    case .mode?: found += (source.modes() + ["back"]).map { CompletionCandidate($0) }
    case .mark?: found += source.marks().map { CompletionCandidate($0) }
    case nil: break
    }
    var seen = Set<String>()
    return .candidates(found.filter { seen.insert($0.word).inserted })
}

public func commandSuggestions(for text: String, source: CompletionSource = CompletionSource()) -> (partial: String, words: [String]) {
    var words = text.split(separator: " ").map(String.init)
    if text.isEmpty || text.hasSuffix(" ") { words.append("") }
    guard case .candidates(let found) = complete(words, source: source) else { return (words.last ?? "", []) }
    let partial = words.last ?? ""
    return (partial, found.map(\.word).filter { $0.hasPrefix(partial) && $0 != partial })
}

private func windowCandidates(_ windows: [LiveWindow]) -> [CompletionCandidate] {
    windows.sorted { $0.id < $1.id }.map {
        CompletionCandidate(String($0.id), String([$0.app, $0.title].filter { !$0.isEmpty }.joined(separator: " - ").prefix(60)))
    }
}

public func renderCompletion(_ result: CompletionResult) -> String {
    func clean(_ text: String) -> String { String(text.map { $0.isNewline || $0 == "\t" ? " " : $0 }) }
    switch result {
    case .command: return "@command\n"
    case .file: return "@file\n"
    case let .candidates(list):
        return list.map { clean($0.word) + ($0.summary.map { "\t" + clean($0) } ?? "") + "\n" }.joined()
    }
}

private func jsonArray(_ data: Data) -> [[String: Any]] {
    (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
}

public func parseLiveWindows(_ json: Data) -> [LiveWindow] {
    jsonArray(json).compactMap { item in
        guard let id = item["id"] as? Int else { return nil }
        return LiveWindow(id: UInt32(id), app: item["app_name"] as? String ?? "", title: item["title"] as? String ?? "")
    }
}

public func parseLiveWorkspaces(_ json: Data) -> [String] {
    jsonArray(json).compactMap { $0["name"] as? String }
}

public func parseLiveMarks(_ json: Data) -> [String] {
    Array(Set(jsonArray(json).flatMap { $0["marks"] as? [String] ?? [] })).sorted()
}

public func parseLiveModes(_ json: Data) -> [String] {
    Array(Set(jsonArray(json).compactMap { $0["mode"] as? String })).sorted()
}

public func completionScript(for shell: CompletionShell) -> String {
    switch shell {
    case .zsh:
        return """
        #compdef wm
        # zsh completion for wm, made by `wm completion zsh`. The candidates come from `wm __complete`.

        _wm() {
            local -a lines described
            local line word summary
            lines=("${(@f)$(command wm __complete "${(@)words[2,CURRENT]}" 2>/dev/null)}")
            case $lines[1] in
                @command) _command_names -e; return ;;
                @file) _files; return ;;
            esac
            for line in $lines; do
                [[ -n $line ]] || continue
                word=${line%%$'\t'*}
                summary=""
                [[ $line == *$'\t'* ]] && summary=${line#*$'\t'}
                described+=("${word//:/\\:}${summary:+:$summary}")
            done
            ((${#described})) && _describe -t wm-candidates 'wm' described
        }

        if [ "$funcstack[1]" = "_wm" ]; then
            _wm "$@"
        else
            compdef _wm wm
        fi

        """
    case .bash:
        return """
        # bash completion for wm, made by `wm completion bash`. The candidates come from `wm __complete`.

        _wm() {
            # COMP_WORDS splits at ':' and '=', so split the line again at blanks only.
            local before="${COMP_LINE:0:COMP_POINT}" words out line cur
            read -ra words <<< "$before"
            [[ "$before" == *[[:space:]] ]] && words+=("")
            cur="${words[${#words[@]}-1]}"
            out="$(command wm __complete "${words[@]:1}" 2>/dev/null)"
            COMPREPLY=()
            case "$out" in
                @command) COMPREPLY=($(compgen -c -- "$cur" | sort -u)); return ;;
                @file) COMPREPLY=($(compgen -f -- "$cur")); return ;;
            esac
            local IFS=$'\n'
            for line in $(compgen -W "$(printf '%s\n' "$out" | cut -f1)" -- "$cur"); do
                line="${line#"${cur%"${cur##*:}"}"}"
                COMPREPLY+=("$(printf '%q' "$line")")
            done
        }

        complete -F _wm wm

        """
    }
}
