import Testing
@testable import Background

#if os(macOS) || os(iOS) || os(tvOS) || os(visionOS)
struct BackgroundTests {
	@Test func registerAndSubmitProcessingTask() throws {
		let identifier = "test-processing-task"
		let request = ProcessingTaskRequest(identifier: identifier)
		
		let scheduler = TaskScheduler.shared
		
		let registered = scheduler.register(forTaskWithIdentifier: identifier) { task in
			
		}
		
		#expect(registered)
		
		try scheduler.submit(request)
	}
}
#endif
