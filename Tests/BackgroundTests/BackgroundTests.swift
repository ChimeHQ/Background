import Testing
@testable import Background

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
