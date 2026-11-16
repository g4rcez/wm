import Darwin

public enum ProcessTree {
    /// Whether `pid` is `ancestor` or one of its descendants. A program that `wm exec` starts is the process that opens
    /// the window, or its parent, so this finds the window that a command opened.
    public static func isDescendant(_ pid: Int32, of ancestor: Int32) -> Bool {
        var current = pid
        for _ in 0..<32 {
            if current == ancestor { return true }
            guard current > 1, let parent = parent(of: current) else { return false }
            current = parent
        }
        return false
    }

    static func parent(of pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
