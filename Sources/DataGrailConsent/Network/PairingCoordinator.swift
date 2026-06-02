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

        // Baseline captured on the first poll so a PRE-EXISTING record (e.g. the
        // device paired before) doesn't instantly complete the flow. Completion
        // requires a NEW write that arrives after the banner opens.
        private var baselineCaptured = false
        private var baselineUpdatedAt: String?  // nil = no record at baseline

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

            Logger.debug("PairingCoordinator: Starting polling for user_hash=\(userHash)")

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
            Logger.debug("PairingCoordinator: Stopping polling")
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
                    // First poll establishes the baseline (record present? which
                    // updated_at?) without completing — otherwise a pre-existing
                    // record would dismiss the banner instantly.
                    if !self.baselineCaptured {
                        self.baselineCaptured = true
                        switch pairingRead {
                        case .notFound:
                            self.baselineUpdatedAt = nil
                        case let .found(_, updatedAt):
                            self.baselineUpdatedAt = updatedAt
                        }
                        Logger.debug("PairingCoordinator: baseline updated_at=\(self.baselineUpdatedAt ?? "none")")
                        return
                    }

                    switch pairingRead {
                    case .notFound:
                        // Still waiting, continue polling
                        Logger.debug("PairingCoordinator: Poll returned not_found, continuing")
                    case let .found(preferences, updatedAt):
                        // Only complete on a NEW write (updated_at changed since
                        // baseline, or a record appeared where there was none).
                        if updatedAt == self.baselineUpdatedAt {
                            Logger.debug("PairingCoordinator: found, but unchanged since baseline — continuing")
                            return
                        }
                        Logger.debug("PairingCoordinator: new write detected, consent received")
                        self.stopPolling()
                        DispatchQueue.main.async {
                            self.onConsentFound?(preferences)
                        }
                    }
                case let .failure(error):
                    // Log error but continue polling (transient network errors)
                    Logger.warn("PairingCoordinator: Poll error: \(error), continuing")
                }
            }
        }

        private func handleTimeout() {
            Logger.warn("PairingCoordinator: Client-side timeout reached (\(timeout)s)")
            stopPolling()
            DispatchQueue.main.async {
                self.onTimeout?()
            }
        }
    }
#endif
