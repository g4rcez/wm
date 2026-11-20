public func makeEngine(_ kind: LayoutKind, settings: Settings) -> any LayoutEngine {
    switch kind {
    case .tiling, .floating: DwindleEngine(settings: settings)
    case .scrolling: ScrollingEngine(settings: settings)
    case .master: MasterEngine(settings: settings)
    case .monocle: MonocleEngine(settings: settings)
    }
}

/// A layout that can be written to disk and built again.
public enum LayoutState: Codable, Sendable {
    case tiling(DwindleEngine.State)
    case floating(DwindleEngine.State)
    case scrolling(ScrollingEngine.State)
    case master(MasterEngine.State)
    case monocle(MonocleEngine.State)

    public var kind: LayoutKind {
        switch self {
        case .tiling: .tiling
        case .floating: .floating
        case .scrolling: .scrolling
        case .master: .master
        case .monocle: .monocle
        }
    }
}

/// The engine that `state` was saved from, with the current settings.
public func makeEngine(restoring state: LayoutState, settings: Settings) -> any LayoutEngine {
    switch state {
    case .tiling(let saved), .floating(let saved): DwindleEngine(settings: settings, state: saved)
    case .scrolling(let saved): ScrollingEngine(settings: settings, state: saved)
    case .master(let saved): MasterEngine(settings: settings, state: saved)
    case .monocle(let saved): MonocleEngine(settings: settings, state: saved)
    }
}
