import Testing
@testable import Background

struct BackgroundTests {
	@Test func testExample() throws {
		let request = ProcessingTaskRequest(identifier: "abc")
		
		let scheduler = TaskScheduler.shared
		
		_ = scheduler.register(forTaskWithIdentifier: "abc") { task in
			
		}
		
		try scheduler.submit(request)
	}
}
