import Foundation

@MainActor
public final class SpaceSwitcher {
    private struct Request {
        let target: UInt64
        let landed: (() -> Void)?
        let startedAt: UInt64
    }

    private struct Flight {
        var request: Request?
        var posted: UInt64?
        var postedAt: UInt64 = 0
        var dockProcess: Int32?
    }

    private let currentSpace: (String) -> UInt64
    private let dockProcess: () -> Int32?
    private let spaceIDs: (String) -> [UInt64]
    private let swipe: (Int32, Int32, String) -> Bool
    private let clock: () -> UInt64
    private let pollAutomatically: Bool
    private let batchMovement: Bool
    private let timeout: UInt64
    private var flights: [String: Flight] = [:]
    private var timer: Timer?
    private var posting = false

    public var onTarget: ((String, UInt64) -> Void)?
    public var onSettled: ((String) -> Void)?
    public var log: (String) -> Void = { _ in }

    public init(
        currentSpace: @escaping (String) -> UInt64, spaceIDs: @escaping (String) -> [UInt64],
        swipe: @escaping (Int32, Int32, String) -> Bool, clock: @escaping () -> UInt64 = SpaceSwitcher.uptime,
        pollAutomatically: Bool = true, batchMovement: Bool, timeout: UInt64 = 2_000_000_000,
        dockProcess: @escaping () -> Int32? = { nil }
    ) {
        self.currentSpace = currentSpace
        self.spaceIDs = spaceIDs
        self.swipe = swipe
        self.clock = clock
        self.pollAutomatically = pollAutomatically
        self.batchMovement = batchMovement
        self.timeout = timeout
        self.dockProcess = dockProcess
    }

    nonisolated public static func uptime() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }

    public func target(on uuid: String) -> UInt64? { flights[uuid]?.request?.target }

    public func destination(on uuid: String) -> UInt64? { target(on: uuid) ?? flights[uuid]?.posted }

    public var switching: Bool { !flights.isEmpty }

    @discardableResult
    public func request(_ target: UInt64, on uuid: String, landed: (() -> Void)? = nil) -> Bool {
        let previous = flights[uuid]?.request?.target
        if flights[uuid] == nil {
            guard currentSpace(uuid) != target else { return false }
            flights[uuid] = Flight()
        }
        flights[uuid]!.request = Request(target: target, landed: landed, startedAt: clock())
        if previous != target { onTarget?(uuid, target) }
        if !posting, flights[uuid]?.posted == nil { post(on: uuid) }
        startPolling()
        return true
    }

    private func post(on uuid: String) {
        guard var flight = flights[uuid], flight.posted == nil, let request = flight.request else { return }
        let spaces = spaceIDs(uuid)
        let current = currentSpace(uuid)
        guard let from = spaces.firstIndex(of: current), let target = spaces.firstIndex(of: request.target) else {
            return finish(uuid, "switch: Space \(request.target) is not on display \(uuid)")
        }
        guard from != target else { return finish(uuid, "switch: display \(uuid) reached Space \(current)", landed: true) }
        let to = batchMovement ? target : from + (target > from ? 1 : -1)
        flight.posted = spaces[to]
        flight.postedAt = clock()
        flight.dockProcess = dockProcess()
        flights[uuid] = flight
        posting = true
        let ok = swipe(Int32(from + 1), Int32(to + 1), uuid)
        posting = false
        if !ok { finish(uuid, "switch: posting the swipe to desktop \(to + 1) failed") }
    }

    public func poll() {
        guard !posting else { return }
        let dock = dockProcess()
        for uuid in Array(flights.keys) {
            guard var flight = flights[uuid] else { continue }
            if let posted = flight.posted {
                guard dock == flight.dockProcess, spaceIDs(uuid).contains(posted) else {
                    finish(uuid, "switch: the desktops changed while waiting for Space \(posted) on display \(uuid)")
                    continue
                }
            }
            if let posted = flight.posted, currentSpace(uuid) == posted {
                flight.posted = nil
                flights[uuid] = flight
            }
            if flight.posted == nil {
                if flight.request == nil {
                    flights.removeValue(forKey: uuid)
                } else {
                    post(on: uuid)
                }
            } else if let posted = flight.posted, let request = flight.request,
                clock() - max(flight.postedAt, request.startedAt) > timeout
            {
                flights[uuid]!.request = nil
                log("switch: gave up on Space \(request.target); waiting for Space \(posted) on display \(uuid)")
                onSettled?(uuid)
            }
        }
        if flights.isEmpty {
            timer?.invalidate()
            timer = nil
        }
    }

    private func finish(_ uuid: String, _ message: String, landed: Bool = false) {
        guard let flight = flights.removeValue(forKey: uuid) else { return }
        log(message)
        if flight.request != nil { onSettled?(uuid) }
        if landed { flight.request?.landed?() }
    }

    private func startPolling() {
        guard pollAutomatically, timer == nil, !flights.isEmpty else { return }
        let timer = Timer(timeInterval: 0.01, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
