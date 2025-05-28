//
//  MyPlacesTests.swift
//  MyPlacesTests
//
//  Created by Jon Guler on 27.01.2025.
//

import XCTest
@testable import MyPlaces

final class MyPlacesTests: XCTestCase {
    
    private let variableManager = VariableManager()
    
    func testFclassConversion (){
        // Given
        let testString = "airport"
        // When
        let result: Double = variableManager.fclassConversion(fclass: testString)
        // Then
        let expectedResult: Double = 1.0
        
        XCTAssertEqual(result, expectedResult)
    }
    
}
