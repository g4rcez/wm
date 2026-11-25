/// The windows to dim: the ones on screen without the focus. A parked window waits at the edge of the screen, and an exempt
/// one asked to stay as it is.
public func windowsToDim(shown: Set<WindowID>, parked: Set<WindowID>, focused: WindowID?, exempt: Set<WindowID>) -> [WindowID] {
    var result = shown.subtracting(parked).subtracting(exempt)
    if let focused { result.remove(focused) }
    return result.sorted()
}
