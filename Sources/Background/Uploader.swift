import Foundation
import OSLog

/// Interface to long-running URLSessionTask objects.
public struct BackgroundTaskConfiguration: Sendable {
	public typealias IdentifierProvider = @Sendable (URLSessionTask) -> String?
	public typealias PrepareTask = @Sendable (URLSessionTask, URLRequest, String) -> Void

	public let getIdentifier: IdentifierProvider
	public let prepareTask: PrepareTask

	public init(
		getIdentifier: @escaping IdentifierProvider,
		prepareTask: @escaping PrepareTask = { _, _, _ in }
	) {
		self.getIdentifier = getIdentifier
		self.prepareTask = prepareTask
	}

	/// Stores a persistent identifier within the `URLSessionTask`'s `taskDescription` property.
	public static let taskDescriptionCoder = BackgroundTaskConfiguration(
		getIdentifier: { $0.taskDescription },
		prepareTask: { $0.taskDescription = $2 }
	)
}

/// Manages background uploads
public actor Uploader {
	public typealias Identifier = String
	public typealias Handler = @Sendable (Identifier, Result<URLResponse, Error>) -> Void

	private let session: URLSession
	private var handlers = [Identifier: Handler]()
	private let logger = Logger(subsystem: "com.chimehq.Background", category: "Uploader")
	private let taskInterface: BackgroundTaskConfiguration

	public init(
		sessionConfiguration: URLSessionConfiguration,
		taskConfiguration: BackgroundTaskConfiguration = BackgroundTaskConfiguration.taskDescriptionCoder
	) {
		let proxy = URLSessionDelegateProxy()

		self.taskInterface = taskConfiguration
		self.session = URLSession(configuration: sessionConfiguration, delegate: proxy, delegateQueue: nil)

		proxy.taskCompletedHandler = { task, error in
			Task {
				await self.taskFinished(task, with: error)
			}
		}
	}

	public init(
		sessionConfiguration: URLSessionConfiguration,
		identifierProvider: @escaping BackgroundTaskConfiguration.IdentifierProvider
	) {
		self.init(
			sessionConfiguration: sessionConfiguration,
			taskConfiguration: BackgroundTaskConfiguration(
				getIdentifier: identifierProvider
			)
		)
	}

	private var activeTasks: Set<String> {
		get async {
            // force a turn of the main runloop, which I have found to sometimes be necessary for this to actually work
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    continuation.resume()
                }
            }

			let (_, uploadTasks, _) = await session.tasks
			let ids = uploadTasks.compactMap { taskInterface.getIdentifier($0) }

			return Set(ids)
		}
	}
}

extension Uploader {
	/// Start the upload task, calling handler when complete.
	///
	/// While this function begins the process, background uploads may never even **begin** until the process has already exited. You should not expect that your handler be called quickly.
	///
	/// You should track pending upload identifiers and re-invoke this method on subsequent launches.
	///
	/// - Warning: there is no guarantee that `handler` is called during this current processes life-cycle. It may only be called on a future launch.
	///
	public func beginUpload(
		of url: URL,
		with request: URLRequest,
		identifier: String,
		handler: @escaping Handler
	) {
		precondition(handlers[identifier] == nil)
		handlers[identifier] = handler

		Task<Void, Never> {
			let ids = await self.activeTasks

			if ids.contains(identifier) {
				logger.debug("found existing task for \(identifier, privacy: .public)")
				return
			}

			let uploadTask = session.uploadTask(with: request, fromFile: url)

			taskInterface.prepareTask(uploadTask, request, identifier)

			uploadTask.resume()
		}
	}

	/// Start the upload task and return the response when complete.
	///
	/// While this function begins the process, background uploads may never even **begin** until the process has already exited. You should not expect that this function will return quickly.
	///
	/// You should track pending upload identifiers and re-invoke this method on subsequent launches.
	///
	/// - Warning: there is no guarantee this function returns during this current processes life-cycle. It may only produce a result on a future launch.
	///
	public func uploadFile(
		at url: URL,
		with request: URLRequest,
		identifier: String
	) async throws -> URLResponse {
		try await withCheckedThrowingContinuation { continuation in
			beginUpload(of: url, with: request, identifier: identifier) { _, response in
				continuation.resume(with: response)
			}
		}
	}

    /// Start the upload task and return a NetworkResponse when complete.
	public func networkResponse(
		from request: URLRequest,
		uploading url: URL,
		with identifier: String
	) async -> NetworkResponse {
		do {
			let response = try await uploadFile(at: url, with: request, identifier: identifier)

			return NetworkResponse(response: response)
		} catch {
			return NetworkResponse(response: nil, error: error)
		}
	}

	private func taskFinished(_ task: URLSessionTask, with error: Error?) {
		guard task is URLSessionUploadTask else { return }
		let identifier = taskInterface.getIdentifier(task) ?? "<nil>"

		logger.info("completed upload task: \(identifier, privacy: .public)")

		let response = task.responseResult(with: error)

		uploadFinished(with: response, identifier: identifier)
	}

	private func uploadFinished(with response: Result<URLResponse, Error>, identifier: Identifier) {
		guard let handler = handlers[identifier] else {
			logger.info("no handler found for \(identifier, privacy: .public)")

			return
		}

		handlers[identifier] = nil
		handler(identifier, response)
	}
}
