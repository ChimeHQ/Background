import Testing
@testable import Background

#if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
struct BackgroundTests {
	@Test func registerAndSubmitProcessingTask() throws {
		let identifier = "abc"
		let request = ProcessingTaskRequest(identifier: identifier)
		
		let scheduler = TaskScheduler.shared
		
		_ = scheduler.register(forTaskWithIdentifier: identifier) { task in
			
		}
		
#if os(macOS)
		try scheduler.submit(request)
#else
		// we know this will throw because we will not have the correct plist entries during testing
		#expect(throws: (any Error).self) {
			try scheduler.submit(request)
		}
#endif
	}
}
#endif
