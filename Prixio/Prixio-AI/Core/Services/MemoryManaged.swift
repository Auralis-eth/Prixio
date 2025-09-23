import Foundation

/// Protocol for services that can manage memory usage
protocol MemoryManaged: AppService {
    var memoryUsage: Int { get }
    func freeMemoryResources()
    func optimizeMemoryUsage()
}
