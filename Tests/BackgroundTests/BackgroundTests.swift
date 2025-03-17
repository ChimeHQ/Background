import Testing
@testable import Background

#if os(iOS) || os(tvOS) || os(visionOS) || os(macOS)
struct BackgroundTests {
	@Test func registerAndSubmitProcessingTask() throws {
		let identifier = "test-processing-task"
		let request = ProcessingTaskRequest(identifier: identifier)
		
		let scheduler = TaskScheduler.shared
		
		let registered = scheduler.register(forTaskWithIdentifier: identifier) { task in
			
		}
		
		// We know that on iOS (non-Catalyst) platforms, the identifier must be in the
		// target's Info.plist for this registration to succeed.
#if os(macOS) || targetEnvironment(macCatalyst)
		#expect(registered)
#endif
		
		guard registered else { return }
		
		try scheduler.submit(request)
	}
}
#endif
