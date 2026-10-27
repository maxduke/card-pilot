#if PERFORMANCE_TESTING && targetEnvironment(simulator)
import os

/// Native timing only in the explicitly isolated simulator performance build.
enum PerformanceSignposts {
    static let transactions = OSSignposter(
        subsystem: "com.maxduke.CardPilot.performance",
        category: "Transaction"
    )
}
#endif
