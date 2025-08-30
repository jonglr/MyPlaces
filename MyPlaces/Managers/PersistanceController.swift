//
//  PersistanceController.swift
//  MyPlaces
//
//  Created by Jon Guler on 08.05.2025.
//

/// **Class Functions**
/// Is used to keep data persistant across the differen objects and classes. This is the Core Data stack manager that handles the fundamental database infrastructure for the application

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
