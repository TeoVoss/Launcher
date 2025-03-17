import XCTest
@testable import Launcher

final class SearchServiceTests: XCTestCase {
    var searchService: SearchService!
    
    override func setUp() {
        super.setUp()
        searchService = SearchService()
    }
    
    override func tearDown() {
        searchService = nil
        super.tearDown()
    }
    
    func testEmptySearchQuery() {
        // 当搜索查询为空时，结果应该为空
        searchService.search(query: "")
        XCTAssertTrue(searchService.searchResults.isEmpty)
        XCTAssertTrue(searchService.categories.isEmpty)
    }
    
    func testCalculatorSearch() {
        // 测试简单的计算表达式
        searchService.search(query: "2 + 2")
        
        // 等待异步搜索完成
        let expectation = XCTestExpectation(description: "Search completion")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertFalse(self.searchService.searchResults.isEmpty)
            let calculatorResults = self.searchService.searchResults.filter { $0.type == .calculator }
            XCTAssertEqual(calculatorResults.count, 1)
            XCTAssertEqual(calculatorResults.first?.calculationResult, "4")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testApplicationSearch() {
        // 测试应用程序搜索
        searchService.search(query: "Safari")
        
        // 等待异步搜索完成
        let expectation = XCTestExpectation(description: "Search completion")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let appResults = self.searchService.searchResults.filter { $0.type == .application }
            XCTAssertFalse(appResults.isEmpty)
            XCTAssertTrue(appResults.contains { $0.name.lowercased().contains("safari") })
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
} 