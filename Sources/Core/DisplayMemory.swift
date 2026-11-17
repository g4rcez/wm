/// The workspace that each display that went away was showing. A display that comes back (the lid opens, a monitor
/// wakes or is plugged again) shows that workspace again, unless another monitor shows it now.
public struct DisplayMemory: Sendable, Equatable {
    private var workspaces: [UInt32: String] = [:]

    public init() {}

    public mutating func lost(_ display: UInt32, workspace: String) {
        workspaces[display] = workspace
    }

    /// The workspace of a display that comes back. The entry is used once.
    public mutating func returning(_ display: UInt32, shown: Set<String>) -> String? {
        guard let name = workspaces.removeValue(forKey: display), !shown.contains(name) else { return nil }
        return name
    }
}
