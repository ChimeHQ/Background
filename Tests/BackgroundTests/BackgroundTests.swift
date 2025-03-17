import Testing
@testable import Background

#if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
struct BackgroundTests {
	@Test func testExample() throws {
		let request = ProcessingTaskRequest(identifier: "abc")
		
		let scheduler = TaskScheduler.shared
		
		_ = scheduler.register(forTaskWithIdentifier: "abc") { task in
			
		}
		
		try scheduler.submit(request)
	}
}
#endif
