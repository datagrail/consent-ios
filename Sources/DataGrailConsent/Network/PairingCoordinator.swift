#if os(tvOS)
    import Foundation

    /// Coordinates the QR pairing flow: manages polling, timeout, and fallback to D-pad banner
    public final class PairingCoordinator {
        // MARK: - Properties

        private let pairingService: PairingService
        private let customerId: String
        private let userHash: String
        private let pollInterval: TimeInterval
        private let timeout: TimeInterval

        private var pollTimer: Timer?
        private var timeoutTimer: Timer?
        private var startTime: Date?

        public var onConsentFound: ((ConsentPreferences) -> Void)?
        public var onTimeout: (() -> Void)?

        // MARK: - Initialization

        /// Initialize the pairing coordinator
        /// - Parameters:
        ///   - pairingService: Service for reading consent
        ///   - customerId: DataGrail customer ID
        ///   - userHash: Device user_hash (64-char hex SHA-256)
        ///   - pollInterval: Time between polls (default 2 seconds)
        ///   - timeout: Client-side timeout (default 10 minutes)
        public init(
            pairingService: PairingService,
            customerId: String,
            userHash: String,
            pollInterval: TimeInterval = 2.0,
            timeout: TimeInterval = 600.0
        ) {
            self.pairingService = pairingService
            self.customerId = customerId
            self.userHash = userHash
            self.pollInterval = pollInterval
            self.timeout = timeout
        }

        // MARK: - Lifecycle

        /// Start polling for consent
        public func startPolling() {
            startTime = Date()

            Logger.log("PairingCoordinator: Starting polling for user_hash=\(userHash)", level: .debug)

            // Schedule polling timer
            pollTimer = Timer.scheduledTimer(
                withTimeInterval: pollInterval,
                repeats: true
            ) { [weak self] _ in
                self?.poll()
            }

            // Schedule timeout timer
            timeoutTimer = Timer.scheduledTimer(
                withTimeInterval: timeout,
                repeats: false
            ) { [weak self] _ in
                self?.handleTimeout()
            }

            // Perform first poll immediately
            poll()
        }

        /// Stop polling (cleanup)
        public func stopPolling() {
            Logger.log("PairingCoordinator: Stopping polling", level: .debug)
            pollTimer?.invalidate()
            pollTimer = nil
            timeoutTimer?.invalidate()
            timeoutTimer = nil
        }

        // MARK: - Polling

        private func poll() {
            pairingService.fetchConsent(customerId: customerId, userHash: userHash) { [weak self] result in
                guard let self = self else { return }

                switch result {
                case let .success(pairingRead):
                    switch pairingRead {
                    case .notFound:
                        // Still waiting, continue polling
                        Logger.log("PairingCoordinator: Poll returned not_found, continuing", level: .debug)
                    case let .found(preferences):
                        // Phone wrote consent, stop polling and notify
                        Logger.log("PairingCoordinator: Poll returned found, consent received", level: .debug)
                        self.stopPolling()
                        DispatchQueue.main.async {
                            self.onConsentFound?(preferences)
                        }
                    }
                case let .failure(error):
                    // Log error but continue polling (transient network errors)
                    Logger.log("PairingCoordinator: Poll error: \(error), continuing", level: .warning)
                }
            }
        }

        private func handleTimeout() {
            Logger.log("PairingCoordinator: Client-side timeout reached (\(timeout)s)", level: .warning)
            stopPolling()
            DispatchQueue.main.async {
                self.onTimeout?()
            }
        }
    }
#endif
