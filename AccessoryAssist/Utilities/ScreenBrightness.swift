import UIKit

/// Takes over screen brightness and the idle timer while barcode scan mode is
/// open, and puts both back exactly as they were on exit.
///
/// mPOS scanners read a dim or auto-dimming screen unreliably, so scan mode
/// raises brightness and blocks auto-lock. Anything that borrows a system-wide
/// setting like this has to be certain to give it back — the restore path runs
/// on dismissal, on backgrounding, and on deinit.
@MainActor
final class ScreenBrightnessController: ObservableObject {

    private var previousBrightness: CGFloat?
    private var previousIdleTimerDisabled: Bool?

    /// The active window scene's screen, avoiding the deprecated `UIScreen.main`.
    private var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .screen
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?
                .screen
    }

    var isActive: Bool { previousBrightness != nil }

    /// Raise brightness for scanning and keep the display awake.
    func beginScanMode(brightness: Double) {
        guard let screen else { return }
        if previousBrightness == nil {
            previousBrightness = screen.brightness
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        }
        screen.brightness = CGFloat(min(max(brightness, 0.1), 1.0))
        UIApplication.shared.isIdleTimerDisabled = true
    }

    /// Restore the brightness and idle timer the device had before scan mode.
    func endScanMode() {
        if let previousBrightness, let screen {
            screen.brightness = previousBrightness
        }
        if let previousIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        }
        previousBrightness = nil
        previousIdleTimerDisabled = nil
    }

    deinit {
        // Belt and braces: if the controller is torn down while scan mode is
        // somehow still active, do not leave the device at full brightness with
        // auto-lock disabled.
        let brightness = previousBrightness
        let idleTimer = previousIdleTimerDisabled
        guard brightness != nil || idleTimer != nil else { return }
        Task { @MainActor in
            if let brightness,
               let screen = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.screen {
                screen.brightness = brightness
            }
            if let idleTimer {
                UIApplication.shared.isIdleTimerDisabled = idleTimer
            }
        }
    }
}
