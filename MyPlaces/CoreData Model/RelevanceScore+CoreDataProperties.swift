//
//  RelevanceScore+CoreDataProperties.swift
//  MyPlaces
//
//  Created by Jon Guler on 18.05.2025.
//
//

import Foundation
import CoreData


extension RelevanceScore {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<RelevanceScore> {
        return NSFetchRequest<RelevanceScore>(entityName: "RelevanceScore")
    }

    @NSManaged public var poiID: UUID?
    @NSManaged public var fid: Int64
    @NSManaged public var score: Double
    @NSManaged public var userID: UUID?
    @NSManaged public var isFavorite: Bool
    @NSManaged public var clickCount: Int32
    @NSManaged public var lastClickedDate: Date?
    @NSManaged public var poi: POI?
    @NSManaged public var user: UserProfile?

}

extension RelevanceScore : Identifiable {

}
