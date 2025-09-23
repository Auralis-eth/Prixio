import Foundation
import SwiftData

//struct PriceEntryQueries {
//    static func latestPrice(forProductID productID: UUID, in context: ModelContext) throws -> PriceEntry? {
//        let descriptor = FetchDescriptor<PriceEntry>(
//            predicate: #Predicate { entry in
//                entry.product?.id == productID && entry.isDeleted == false
//            },
//            sortBy: [SortDescriptor(\.captureDate, order: .reverse)],
//            fetchLimit: 1
//        )
//        return try context.fetch(descriptor).first
//    }
//
//    static func latestPrice(forStoreID storeID: UUID, in context: ModelContext) throws -> PriceEntry? {
//        let descriptor = FetchDescriptor<PriceEntry>(
//            predicate: #Predicate { entry in
//                entry.store?.id == storeID && entry.isDeleted == false
//            },
//            sortBy: [SortDescriptor(\.captureDate, order: .reverse)],
//            fetchLimit: 1
//        )
//        return try context.fetch(descriptor).first
//    }
//}
