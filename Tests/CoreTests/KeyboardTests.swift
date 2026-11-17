import Testing
@testable import Core

struct KeyboardTests {
    private let builtIn = KeyboardInfo(name: "Apple Internal Keyboard / Trackpad", transport: "FIFO", isBuiltIn: true)
    private let logitech = KeyboardInfo(name: "USB Receiver", vendorID: 0x046d, productID: 0xc52b, transport: "USB")

    @Test func theIdIsVendorAndProductInHex() {
        #expect(logitech.id == "046d:c52b")
        #expect(builtIn.id == "0000:0000")
    }

    @Test func everyKeyboardIsEnabledUnlessTheConfigSaysNo() {
        let settings = KeyboardSettings()
        #expect(settings.isEnabled(builtIn))
        #expect(settings.isEnabled(logitech))
    }

    @Test func aNameTurnsOneKeyboardOff() {
        let settings = KeyboardSettings(overrides: ["usb receiver": false])
        #expect(settings.isEnabled(logitech) == false)
        #expect(settings.isEnabled(builtIn))
    }

    @Test func theIdWinsOverTheName() {
        let settings = KeyboardSettings(overrides: ["046d:c52b": true, "usb receiver": false])
        #expect(settings.isEnabled(logitech))
    }

    @Test func aDefaultOfFalseTurnsOnlyTheNamedKeyboardsOn() {
        let settings = KeyboardSettings(defaultEnabled: false, overrides: ["apple internal keyboard / trackpad": true])
        #expect(settings.isEnabled(builtIn))
        #expect(settings.isEnabled(logitech) == false)
    }

    @Test func aKeyboardWithoutTheMappingGetsIt() {
        let plan = KeyboardPlan.plan([builtIn], settings: KeyboardSettings())
        #expect(plan.map(\.action) == [.map])
    }

    @Test func aKeyboardThatHasTheMappingIsLeftAlone() {
        var mapped = builtIn
        mapped.hyperMapped = true
        #expect(KeyboardPlan.plan([mapped], settings: KeyboardSettings()).map(\.action) == [.leave])
    }

    @Test func aDisabledKeyboardLosesTheMappingOnlyWhenItHasOne() {
        var mapped = logitech
        mapped.hyperMapped = true
        let settings = KeyboardSettings(overrides: ["046d:c52b": false])
        #expect(KeyboardPlan.plan([mapped, builtIn], settings: settings).map(\.action) == [.clear, .map])
        #expect(KeyboardPlan.plan([logitech], settings: settings).map(\.action) == [.leave])
    }
}
