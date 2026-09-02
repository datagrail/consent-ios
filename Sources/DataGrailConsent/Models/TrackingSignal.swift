import Foundation
#if canImport(AppTrackingTransparency)
    import AppTrackingTransparency
#endif

/// The device's live opt-out signal, as read from the operating system.
///
/// **There is no GPC on iOS.** GPC (`navigator.globalPrivacyControl` / `Sec-GPC`) is a
/// web-browser signal; a native app has no equivalent. iOS's OS-level signal is App
/// Tracking Transparency, which is narrower (cross-app tracking / IDFA rather than
/// do-not-sell) and has FOUR states rather than a boolean. Modeling it as `gpc: Bool`
/// loses the distinction that matters most: "the user declined tracking" and "the user
/// has not been asked yet" are not the same thing, and only one of them is an opt-out.
///
/// A live signal is not a stored choice. It belongs to this device, is re-read every
/// session, and is never something the user picked in a consent banner.
public enum TrackingSignal: String, Equatable, Sendable {
    /// The ATT prompt has not been answered yet. **Not** an opt-out — absence of a
    /// decision is not consent, and it is not a refusal either.
    case notDetermined

    /// Tracking is restricted at the device level (MDM, parental controls). Treated as
    /// an opt-out: the user cannot be tracked.
    case restricted

    /// The user explicitly declined tracking. An opt-out.
    case denied

    /// The user explicitly permitted tracking. This grants permission to track — it is
    /// NOT consent to marketing categories, and it never turns a stored opt-out into an
    /// opt-in. Signals may only suppress.
    case authorized

    /// Whether this signal asserts an opt-out, i.e. whether it must suppress
    /// non-essential categories.
    ///
    /// `authorized` does not suppress, but it also does not grant. `notDetermined`
    /// deliberately does not suppress: treating an unanswered prompt as a refusal would
    /// silently opt out every user who has not yet seen it.
    public var suppressesNonEssential: Bool {
        switch self {
        case .denied, .restricted:
            return true
        case .authorized, .notDetermined:
            return false
        }
    }
}

/// Reads the device's live tracking signal from the OS.
///
/// The SDK reads this itself so integrators do not have to: passing the wrong value —
/// or defaulting it to `false` — silently disables the suppression that the signal
/// exists to enforce. Callers may still override it when they manage ATT themselves.
public enum TrackingSignalReader {
    /// The current ATT authorization status, without prompting.
    ///
    /// Never prompts, so it is safe to call at any point in the app lifecycle, including
    /// before the ATT prompt has been shown. Returns `.notDetermined` on iOS 13, where
    /// ATT does not exist — the framework is weak-linked via `canImport` +
    /// `@available`, so the SDK keeps its iOS 13 deployment target.
    public static func current() -> TrackingSignal {
        #if canImport(AppTrackingTransparency)
            if #available(iOS 14, tvOS 14, macOS 11, *) {
                switch ATTrackingManager.trackingAuthorizationStatus {
                case .notDetermined:
                    return .notDetermined
                case .restricted:
                    return .restricted
                case .denied:
                    return .denied
                case .authorized:
                    return .authorized
                @unknown default:
                    // A state Apple adds later is not knowably an opt-out. Falling back
                    // to .notDetermined keeps us from inventing a refusal the user
                    // never expressed.
                    return .notDetermined
                }
            }
        #endif
        return .notDetermined
    }

    /// Present the system ATT prompt, then report the resulting signal.
    ///
    /// The host app owns *when* this happens — prompt timing is an App Store review
    /// concern and the prompt only appears once per install, so the SDK will not fire it
    /// on your behalf. Requires an `NSUserTrackingUsageDescription` string in your
    /// `Info.plist`; without it the prompt does not appear.
    ///
    /// Resolves to the current status without prompting on iOS 13, and immediately if the
    /// user has already answered. The completion is invoked on an arbitrary queue.
    public static func requestAuthorization(completion: @escaping (TrackingSignal) -> Void) {
        #if canImport(AppTrackingTransparency)
            if #available(iOS 14, tvOS 14, macOS 11, *) {
                ATTrackingManager.requestTrackingAuthorization { _ in
                    // Read the status back rather than mapping the callback value, so the
                    // four-state mapping lives in exactly one place.
                    completion(current())
                }
                return
            }
        #endif
        completion(current())
    }
}
