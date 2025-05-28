//
//  VariableTests.swift
//  MyPlacesTests
//
//  Created by Jon Guler on 27.01.2025.
//

import XCTest
@testable import MyPlaces

final class VariablesTests: XCTestCase {
    
    func testFClassConversion() {
        // Arrange (Given)
        let flcass = "airfield"
        let variableManager = VariableManager()
        // Act (When)
        let convFclass = variableManager.fclassConversion(fclass: flcass)
        // Assert (Then)
        XCTAssertEqual(convFclass, 0.0)
    }
    
    
    
}
