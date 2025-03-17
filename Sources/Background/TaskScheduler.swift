import Foundation
#if os(iOS) || os(tvOS) || os(visionOS)
import BackgroundTasks
#endif

protocol BackgroundTaskRequest: Hashable {
	var identifier: String { get }
	var earliestBeginDate: Date? { get }
}

enum TaskSchedulerError: Error {
	case unsupportedRequest
	case notSupported
}

#if os(iOS) || os(tvOS) || os(visionOS)
struct BackgroundTask {
	private let task: BGTask
	
	init(_ task: BGTask) {
		self.task = task
	}
	
	public var identifier: String { task.identifier }
	
	public var expirationHandler: (@Sendable () -> Void)? {
		get {
			unsafeBitCast(task.expirationHandler, to: (@Sendable () -> Void)?.self)
		}
		set { task.expirationHandler = newValue }
	}
	
	public func setTaskCompleted(success: Bool) {
		task.setTaskCompleted(success: success)
	}
}

extension BackgroundTaskRequest {
	var bgTaskRequest: BGTaskRequest {
		get throws {
			switch self {
			case is AppRefreshTaskRequest:
				let request = BGAppRefreshTaskRequest(identifier: identifier)
				
				request.earliestBeginDate = earliestBeginDate
				
				return request
			case let processing as ProcessingTaskRequest:
				let request = BGProcessingTaskRequest(identifier: identifier)
				
				request.earliestBeginDate = earliestBeginDate
				request.requiresNetworkConnectivity = processing.requiresNetworkConnectivity
				request.requiresExternalPower = processing.requiresExternalPower
				
				return request
			default:
				throw TaskSchedulerError.unsupportedRequest
			}
		}
	}
}
#else
struct BackgroundTask {
	public let identifier: String
	public let expirationHandler: (@Sendable () -> Void)?
	
	public func setTaskCompleted(success: Bool) {
	}
}
#endif

struct AppRefreshTaskRequest: BackgroundTaskRequest {
	public let identifier: String
	public var earliestBeginDate: Date?
	
	init(identifier: String) {
		self.identifier = identifier
	}
}

struct ProcessingTaskRequest: BackgroundTaskRequest {
	public let identifier: String
	public var earliestBeginDate: Date?
	public var requiresNetworkConnectivity: Bool = false
	public var requiresExternalPower: Bool = false
	
	init(identifier: String) {
		self.identifier = identifier
	}
}

#if os(iOS) || os(tvOS) || os(visionOS)
final class TaskScheduler: Sendable {
	public static let shared = TaskScheduler()

	private init() {
	}
	
	public func submit(_ task: any BackgroundTaskRequest) throws {
#if targetEnvironment(simulator)
		return
#else
		let bgTaskRequest = try task.bgTaskRequest
		
		try BGTaskScheduler.shared.submit(bgTaskRequest)
#endif
	}
	
	public func register(
		forTaskWithIdentifier identifier: String,
		using queue: dispatch_queue_t? = nil,
		launchHandler: @escaping @Sendable (BackgroundTask) -> Void
	) -> Bool {
#if targetEnvironment(simulator)
		return true
#else
		
		BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: queue) { @Sendable bgTask in
			let task = BackgroundTask(bgTask)
			
			launchHandler(task)
		}
#endif
	}
}
#endif

#if os(iOS) || os(tvOS) || os(visionOS)
extension BGTaskScheduler {
	public func register(
		forTaskWithIdentifier identifier: String,
		launchHandler: @escaping @Sendable (BGTask) -> Void
	) -> Bool {
		register(forTaskWithIdentifier: identifier, using: nil, launchHandler: launchHandler)
	}
}
#endif

#if os(macOS)
final class TaskScheduler: @unchecked Sendable {
	public static let shared = TaskScheduler()
	
	private let scheduler = NSBackgroundActivityScheduler(identifier: "com.chimehq.Background")
	private let lock = NSLock()
	private var requests: [String: any BackgroundTaskRequest] = [:]
	private var registrations: [String: HandlerRegistration] = [:]
	
	private struct HandlerRegistration: Sendable {
		let handler: @Sendable (BackgroundTask) -> Void
		let identifier: String
		let queue: dispatch_queue_t?
	}

	private init() {
	}
	
	public func submit<T: BackgroundTaskRequest>(_ task: T) throws {
		lock.withLock {
			requests[task.identifier] = task
		}
	}
	
	public func register(
		forTaskWithIdentifier identifier: String,
		using queue: dispatch_queue_t? = nil,
		launchHandler: @escaping @Sendable (BackgroundTask) -> Void
	) -> Bool {
		let registration = HandlerRegistration(handler: launchHandler, identifier: identifier, queue: queue)
		
		lock.withLock {
			registrations[identifier] = registration
		}
		
		return true
	}
}
#endif
