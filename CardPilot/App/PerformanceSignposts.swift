#if PERFORMANCE_TESTING && targetEnvironment(simulator)
import os

/// Native timing only in the explicitly isolated simulator performance build.
enum PerformanceSignposts {
    #if TRANSACTION_WRITING_DIAGNOSTIC
    static let lifecycle = Logger(
        subsystem: "com.maxduke.CardPilot.performance", category: "Lifecycle"
    )
    #endif
    static let transactions = OSSignposter(
        subsystem: "com.maxduke.CardPilot.performance",
        category: "Transaction"
    )
}
#endif
