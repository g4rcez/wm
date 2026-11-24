import Foundation

public enum WorkspaceMode: String, Sendable, CaseIterable, Codable {
    case emulated, native
}

public struct NativeDisplay: Sendable, Equatable {
    public var uuid: String
    public var displayID: UInt32
    public var minX: Double
    public var current: UInt64
    public var spaces: [UInt64]

    public init(uuid: String, displayID: UInt32, minX: Double, current: UInt64, spaces: [UInt64]) {
        self.uuid = uuid
        self.displayID = displayID
        self.minX = minX
        self.current = current
        self.spaces = spaces
    }
}

public struct NativeSpaceBinding: Sendable, Equatable {
    public struct Desktop: Sendable, Equatable {
        public var number: Int
        public var space: UInt64
        public var display: String
        public var displayID: UInt32
    }

    public private(set) var desktops: [Desktop] = []
    private var numbers: [String: Int] = [:]
    private var names: [Int: String] = [:]
    public private(set) var displays: [NativeDisplay]

    public init(displays: [NativeDisplay], rules: [String: Int] = [:]) {
        self.displays = displays.sorted { $0.minX < $1.minX }
        var number = 0
        for display in self.displays {
            for space in display.spaces {
                number += 1
                desktops.append(Desktop(number: number, space: space, display: display.uuid, displayID: display.displayID))
            }
        }
        for (name, desktop) in rules.sorted(by: { $0.key < $1.key }) where desktop >= 1 && names[desktop] == nil {
            numbers[name] = desktop
            names[desktop] = name
        }
        for desktop in desktops where names[desktop.number] == nil {
            let name = String(desktop.number)
            if numbers[name] == nil {
                numbers[name] = desktop.number
                names[desktop.number] = name
            }
        }
    }

    public var count: Int { desktops.count }

    public func desktop(of workspace: String) -> Desktop? {
        numbers[workspace].flatMap { number in desktops.first { $0.number == number } }
    }

    public func workspace(of space: UInt64) -> String? {
        desktops.first { $0.space == space }.flatMap { names[$0.number] }
    }

    public func workspaces(on display: String) -> [String] {
        desktops.filter { $0.display == display }.compactMap { names[$0.number] }
    }

    public func missing(_ wanted: [String]) -> [String] {
        wanted.filter { desktop(of: $0) == nil }
    }

    public func display(of space: UInt64) -> NativeDisplay? {
        displays.first { $0.spaces.contains(space) || $0.current == space }
    }
}
