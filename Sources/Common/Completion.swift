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
    /// The shell completes a command name.
    case command
    /// The shell completes a file name.
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

/// What only the running daemon knows. Each closure runs only when the word under the cursor needs it.
public struct CompletionSource {
    public var windows: () -> [LiveWindow] = { [] }
    public var workspaces: () -> [String] = { [] }
    public var modes: () -> [String] = { [] }
    public var marks: () -> [String] = { [] }

    public init() {}
}

private enum LiveArgument { case window, workspace, special, mode, mark }

/// The commands whose first argument is a name or an id that the daemon knows.
private let liveArguments: [String: LiveArgument] = [
    "focus window": .window,
    "workspace": .workspace,
    "window send workspace": .workspace,
    "workspace special": .special,
    "mode": .mode,
    "focus mark": .mark,
    "window unmark": .mark,
]

/// What a shell completes after the words of one command: the next words, the values of the first argument, the options.
private struct CompletionNode {
    var children: [(word: String, summary: String?)] = []
    var values: [String] = []
    var flags: [String] = []
}

private let monitorWords = ["left", "right", "up", "down", "next", "prev", "last", "main", "secondary", "tertiary"]

/// Arguments that `CommandSpec.args` cannot list: the text of the spec names a placeholder, or describes them in `details`.
private let extraValues: [String: [String]] = [
    "list": ["windows", "workspaces", "monitors", "keyboards", "memory", "binds"],
    "query": ["windows", "workspaces", "monitors", "keyboards", "memory"],
    "zen": ["on", "off"],
    "init": ["i3"],  // a word with a digit is not a literal value of the spec
    "window snap": ["left", "right", "top", "bottom", "top-left", "top-right", "bottom-left", "bottom-right", "center"],
    "workspace": ["next", "prev", "empty"],
    "window send workspace": ["next", "prev", "empty"],
    "focus monitor": monitorWords,
    "window send monitor": monitorWords,
    "workspace move monitor": monitorWords,
    "layout tile": ["2", "3", "4", "5", "6", "2+1", "1+2", "2/3", "3/4", "1/4", "center"],
]

private let extraFlags: [String: [String]] = [
    "exec": ["--float", "--tile", "--center", "--maximize", "--no-focus", "--workspace", "--monitor", "--width", "--size", "--layout"],
]

private let directionNames = ["left", "right", "up", "down"]
private let placeholders: Set<String> = ["name", "pattern", "fraction", "n"]
private let globalFlags = ["--window", "--json", "--verbose", "--help"]
private let windowSelectors = ["focused", "app:", "title:", "pid:"]

/// The words that `<a|b|c>` or `[a|b]` stands for. `dir` is the four directions; `<name>` and `<0.1-0.9>` give nothing.
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

/// One node per command prefix, built from `commandSpecs`. The key of the root is the empty string.
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
                    node.children.append((words[depth], isLeaf ? spec.summary : nil))
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


/// The candidates for the last word of `words` (the words after `wm`, the last one being the word under the cursor).
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

private func windowCandidates(_ windows: [LiveWindow]) -> [CompletionCandidate] {
    windows.sorted { $0.id < $1.id }.map {
        CompletionCandidate(String($0.id), String([$0.app, $0.title].filter { !$0.isEmpty }.joined(separator: " - ").prefix(60)))
    }
}

/// The text that `wm __complete` prints: one candidate per line (`word<TAB>summary`), or `@command` or `@file`.
public func renderCompletion(_ result: CompletionResult) -> String {
    func clean(_ text: String) -> String { String(text.map { $0.isNewline || $0 == "\t" ? " " : $0 }) }
    switch result {
    case .command: return "@command\n"
    case .file: return "@file\n"
    case let .candidates(list):
        return list.map { clean($0.word) + ($0.summary.map { "\t" + clean($0) } ?? "") + "\n" }.joined()
    }
}

// MARK: - What the daemon says

private func jsonArray(_ data: Data) -> [[String: Any]] {
    (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
}

/// The `wm list windows --json` document.
public func parseLiveWindows(_ json: Data) -> [LiveWindow] {
    jsonArray(json).compactMap { item in
        guard let id = item["id"] as? Int else { return nil }
        return LiveWindow(id: UInt32(id), app: item["app_name"] as? String ?? "", title: item["title"] as? String ?? "")
    }
}

/// The `wm list workspaces --json` document.
public func parseLiveWorkspaces(_ json: Data) -> [String] {
    jsonArray(json).compactMap { $0["name"] as? String }
}

/// The `wm list windows --json` document: every mark of every window.
public func parseLiveMarks(_ json: Data) -> [String] {
    Array(Set(jsonArray(json).flatMap { $0["marks"] as? [String] ?? [] })).sorted()
}

/// The `wm list binds --json` document: every mode that has a bind.
public func parseLiveModes(_ json: Data) -> [String] {
    Array(Set(jsonArray(json).compactMap { $0["mode"] as? String })).sorted()
}

// MARK: - The scripts

/// The script that `wm completion <shell>` prints. It only asks `wm __complete` for the candidates, so the script
/// never goes out of date, also when a shell caches it (`znap eval`).
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
