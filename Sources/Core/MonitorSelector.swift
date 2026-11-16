import Foundation

/// How a rule names a monitor: its number (1 is the leftmost) or part of its name, ignoring case.
public enum MonitorSelector {
    public static func matches(_ spec: String, index: Int, name: String) -> Bool {
        if let number = Int(spec) { return number == index + 1 }
        return name.range(of: spec, options: .caseInsensitive) != nil
    }
}
