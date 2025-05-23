//
//  UserProfile+CoreDataProperties.swift
//  MyPlaces
//
//  Created by Jon Guler on 18.05.2025.
//
//

import Foundation
import CoreData


extension UserProfile {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<UserProfile> {
        return NSFetchRequest<UserProfile>(entityName: "UserProfile")
    }

    @NSManaged public var email: String?
    @NSManaged public var name: String?
    @NSManaged public var theme: String?
    @NSManaged public var userID: UUID?
    @NSManaged public var relevanceScores: NSSet?

}

// MARK: Generated accessors for relevanceScores
extension UserProfile {

    @objc(addRelevanceScoresObject:)
    @NSManaged public func addToRelevanceScores(_ value: RelevanceScore)

    @objc(removeRelevanceScoresObject:)
    @NSManaged public func removeFromRelevanceScores(_ value: RelevanceScore)

    @objc(addRelevanceScores:)
    @NSManaged public func addToRelevanceScores(_ values: NSSet)

    @objc(removeRelevanceScores:)
    @NSManaged public func removeFromRelevanceScores(_ values: NSSet)

}

extension UserProfile : Identifiable {

}
