//
//  POI+CoreDataProperties.swift
//  MyPlaces
//
//  Created by Jon Guler on 18.05.2025.
//
//

import Foundation
import CoreData


extension POI {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<POI> {
        return NSFetchRequest<POI>(entityName: "POI")
    }

    @NSManaged public var clickCount: Int32
    @NSManaged public var favorite: Bool
    @NSManaged public var lastClickedDate: Date?
    @NSManaged public var poiID: UUID?
    @NSManaged public var relevance: NSSet?

}

// MARK: Generated accessors for relevance
extension POI {

    @objc(addRelevanceObject:)
    @NSManaged public func addToRelevance(_ value: RelevanceScore)

    @objc(removeRelevanceObject:)
    @NSManaged public func removeFromRelevance(_ value: RelevanceScore)

    @objc(addRelevance:)
    @NSManaged public func addToRelevance(_ values: NSSet)

    @objc(removeRelevance:)
    @NSManaged public func removeFromRelevance(_ values: NSSet)

}

extension POI : Identifiable {

}
