//
//  PersistanceController.swift
//  MyPlaces
//
//  Created by Jon Guler on 08.05.2025.
//

import CoreData

class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    private init() {
        container = NSPersistentContainer(name: "MyPlacesModel")
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("CoreData error: \(error.localizedDescription)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
