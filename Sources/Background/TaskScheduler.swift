import Foundation
#if os(iOS) || os(tvOS) || os(visionOS)
import BackgroundTasks
#endif

enum BackgroundTask {

}

final class TaskScheduler: Sendable {
	public static let shared = TaskScheduler()

	private init() {
	}
}
