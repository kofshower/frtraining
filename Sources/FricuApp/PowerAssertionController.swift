import Foundation

#if os(macOS)
    import IOKit.pwr_mgt
#endif

#if os(iOS)
    import UIKit
#endif

final class PowerAssertionController {
    static let shared = PowerAssertionController()

    private init() {}

    #if os(macOS)
        private var assertionID: IOPMAssertionID = 0
        private var isPreventingDisplaySleep = false
    #endif

    func beginPreventingSleep() {
        #if os(macOS)
            guard !isPreventingDisplaySleep else { return }

            let reason = "Fricu keeps display awake while the app is running" as CFString
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &assertionID
            )

            if result == kIOReturnSuccess {
                isPreventingDisplaySleep = true
            }
        #elseif os(iOS)
            DispatchQueue.main.async {
                UIApplication.shared.isIdleTimerDisabled = true
            }
        #endif
    }

    func endPreventingSleep() {
        #if os(macOS)
            guard isPreventingDisplaySleep else { return }
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            isPreventingDisplaySleep = false
        #elseif os(iOS)
            DispatchQueue.main.async {
                UIApplication.shared.isIdleTimerDisabled = false
            }
        #endif
    }
}
