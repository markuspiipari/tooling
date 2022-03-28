///
/// Tooling
/// Copyright © Markus Piipari & Matias Piipari 2016-2021. MIT license, see LICENSE.md for details.
/// File status: Experimental
///

import Foundation

public extension OperationQueue {
    /// Create a named operation queue. Quality of service defaults to `.background`, as per Apple's documentation,
    /// and maximum concurrent operation count to `defaultMaxConcurrentOperationCount`.
    static func makeOperationQueue(
        named name: String,
        qualityOfService: QualityOfService? = nil,
        maximumConcurrency: Int? = nil
    ) -> OperationQueue {
        // Temporarily comment this in for Timelane profiling
        // let q = LaneOperationQueue()

        // Use this when not profiling
        let q = OperationQueue()
        q.name = name
        q.qualityOfService = qualityOfService ?? .background // The default value is documented by Apple to be .background
        q.maxConcurrentOperationCount = maximumConcurrency ?? defaultMaxConcurrentOperationCount

        return q
    }

    /// Create a named operation queue with a maximum concurrent operation count of 1.
    /// See `makeOperationQueue()` for more.
    static func serialOperationQueue(named name: String, qualityOfService: QualityOfService? = nil) -> OperationQueue {
        OperationQueue.makeOperationQueue(named: name, qualityOfService: qualityOfService, maximumConcurrency: 1)
    }
}
