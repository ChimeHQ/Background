import Foundation
import os.log

/// Intermeidate object to use an actor type as a URLSessionDelegate
final class URLSessionDelegateWrapper: NSObject, Sendable {
	let finishHandler: @Sendable () -> Void
	let taskCompletedHandler: @Sendable (URLSessionTask, Error?) -> Void
	let downloadFinishedHandler: @Sendable (URLSessionDownloadTask, URL) -> Void

	init(
		finishHandler: @escaping @Sendable () -> Void,
		taskCompletedHandler: @escaping @Sendable (URLSessionTask, Error?) -> Void,
		downloadFinishedHandler: @escaping @Sendable (URLSessionDownloadTask, URL) -> Void
	) {
		self.finishHandler = finishHandler
		self.taskCompletedHandler = taskCompletedHandler
		self.downloadFinishedHandler = downloadFinishedHandler
	}
}

extension URLSessionDelegateWrapper: URLSessionDelegate {
	func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
		finishHandler()
	}
}

extension URLSessionDelegateWrapper: URLSessionTaskDelegate {
	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		taskCompletedHandler(task, error)
	}
}

extension URLSessionDelegateWrapper: URLSessionDownloadDelegate {
	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
		downloadFinishedHandler(downloadTask, location)
	}
}

enum TransferAgentError: Error {
	case noResponse
	case identifierUnavailable
	case expectedHTTPResponse(URLResponse)
}

public actor TransferAgent {
	private static let defaultRetryInterval: TimeInterval = 5 * 60.0

	public typealias DownloadResponse = Result<(URL, URLResponse), Error>
	public typealias DownloadHandler = @Sendable (String, DownloadResponse) -> Void
	public typealias DownloadHTTPResponse = Result<(URL, HTTPURLResponse), Error>
	public typealias DownloadHTTPHandler = @Sendable (String, DownloadHTTPResponse) -> Void

	public typealias UploadResponse = Result<URLResponse, Error>
	public typealias UploadHandler = @Sendable (String, UploadResponse) -> Void
	public typealias UploadHTTPResponse = Result<HTTPURLResponse, Error>
	public typealias UploadHTTPHandler = @Sendable (String, UploadHTTPResponse) -> Void

	public typealias TaskIdentifierProvider = @Sendable (URLSessionTask) -> String?

	private let logger = Logger(subsystem: "com.chimehq.Background", category: "TransferAgent")
	private var downloadHandlers = [String: DownloadHandler]()
	private var uploadHandlers = [String: UploadHandler]()
	private var pendingEvents = true
	private var sessionCompletionHandler: @Sendable () -> Void = {}
	private let sessionConfiguration: URLSessionConfiguration

	private lazy var delegateWrapper: URLSessionDelegateWrapper = {
		URLSessionDelegateWrapper(
			finishHandler: { [unowned self] in Task { await self.finishedEvents() } },
			taskCompletedHandler: { [unowned self] task, error in Task { await self.taskComplete(task, error) } },
			downloadFinishedHandler: { [unowned self] task, url in Task { await self.downloadFinished(task, url) } }
		)
	}()

	private lazy var session = URLSession(
		configuration: sessionConfiguration,
		delegate: delegateWrapper,
		delegateQueue: nil
	)

	private let taskIdentifierProvider: TaskIdentifierProvider
	public var retryIntervalProvider: @Sendable (URLSessionTask) -> TimeInterval? = { _ in TransferAgent.defaultRetryInterval }

	public init(
		configuration: URLSessionConfiguration,
		taskIdentifierProvider: @escaping TaskIdentifierProvider = { $0.taskDescription }
	) {
		self.sessionConfiguration = configuration
		self.taskIdentifierProvider = taskIdentifierProvider
	}
}

extension TransferAgent {
	private func sessionDidFinishEvents() {
		sessionCompletionHandler()
		self.pendingEvents = false
	}

	private func taskComplete(_ task: URLSessionTask, _ error: Error?) {
		guard let error = error else { return }

		guard let identifier = taskIdentifierProvider(task) else {
			handleAbandonedTask(task, identifier: nil)
			return
		}

		let response = NetworkResponse(task: task, error: error)

		switch response {
		case .success:
			// handled by the task-specific delegate call
			break
		case let .failed(error):
			relayError(error, for: identifier, task: task)
		case .rejected:
			relayError(NetworkResponseError.requestInvalid, for: identifier, task: task)
		case .retry:
			let interval = retryIntervalProvider(task)

			relayError(NetworkResponseError.transientFailure(interval), for: identifier, task: task)
		}
	}

	private func relayError(_ error: Error, for identifier: String, task: URLSessionTask) {
		switch task {
		case is URLSessionDownloadTask:
			relayDownloadResponse(.failure(error), for: identifier, task: task)
		case is URLSessionUploadTask:
			break
		default:
			preconditionFailure("Only upload and download tasks should be possible")
		}
	}

	private func handleAbandonedTask(_ task: URLSessionTask, identifier: String?) {
		logger.warning("task has been abandonded: \(identifier ?? "<nil>", privacy: .public)")
	}

	public func finishedEvents() async {
		if pendingEvents == false {
			logger.debug("skipping pending events")
			return
		}

		await withCheckedContinuation { continuation in
			self.sessionCompletionHandler = {
				continuation.resume()
			}
		}
	}

	public func handleBackgroundSessionEvents(_ completion: @escaping () -> Void) {
		Task {
			await finishedEvents()

			completion()
		}
	}
}

extension TransferAgent {
	public func beginDownload(
		with request: URLRequest,
		identifier: String,
		configureTask: @escaping (URLSessionDownloadTask) -> Void = { _ in },
		handler: @escaping DownloadHandler
	) {
		precondition(downloadHandlers[identifier] == nil)

		downloadHandlers[identifier] = handler

		Task {
			let (_, _, downloadTasks) = await session.tasks
			let ids = Set(downloadTasks.compactMap { taskIdentifierProvider($0) })

			if ids.contains(identifier) {
				logger.debug("found existing task for \(identifier, privacy: .public)")
				return
			}

			let task = self.session.downloadTask(with: request)

			configureTask(task)
			if task.taskDescription != nil {
				logger.warning("taskDescription field is in use and will be overwritten \(identifier, privacy: .public)")
			}

			task.taskDescription = identifier

			task.resume()
		}
	}

	public func beginHTTPDownload(
		with request: URLRequest,
		identifier: String,
		configureTask: @escaping (URLSessionDownloadTask) -> Void = { _ in },
		handler: @escaping DownloadHTTPHandler
	) {
		beginDownload(with: request, identifier: identifier, configureTask: configureTask) { _, response in
			switch response {
			case let .failure(error):
				handler(identifier, .failure(error))
			case let .success((data, response)):
				if let httpResponse = response as? HTTPURLResponse {
					handler(identifier, .success((data, httpResponse)))
				} else {
					handler(identifier, .failure(TransferAgentError.expectedHTTPResponse(response)))
				}
			}
		}
	}

	private func downloadFinished(_ downloadTask: URLSessionDownloadTask, _ location: URL) {
		guard let identifier = taskIdentifierProvider(downloadTask) else {
			handleAbandonedTask(downloadTask, identifier: nil)

			return
		}

		logger.info("completed download task: \(identifier, privacy: .public)")

		guard let response = downloadTask.response else {
			relayDownloadResponse(.failure(TransferAgentError.noResponse), for: identifier, task: downloadTask)

			return
		}

		relayDownloadResponse(.success((location, response)), for: identifier, task: downloadTask)

		try? FileManager.default.removeItem(at: location)
	}

	private func relayDownloadResponse(_ response: DownloadResponse, for identifier: String, task: URLSessionTask) {
		guard let handler = downloadHandlers[identifier] else {
			self.handleAbandonedTask(task, identifier: identifier)
			return
		}

		handler(identifier, response)
	}
}

extension TransferAgent {
	public func beginUpload(
		at url: URL,
		with request: URLRequest,
		identifier: String,
		configureTask: @escaping (URLSessionUploadTask) -> Void = { _ in },
		handler: @escaping UploadHandler
	) {
		precondition(uploadHandlers[identifier] == nil)

		uploadHandlers[identifier] = handler

		Task {
			let (_, uploadTasks, _) = await session.tasks
			let ids = Set(uploadTasks.compactMap { taskIdentifierProvider($0) })

			if ids.contains(identifier) {
				logger.debug("found existing task for \(identifier, privacy: .public)")
				return
			}

			let task = self.session.uploadTask(with: request, fromFile: url)

			configureTask(task)
			if task.taskDescription != nil {
				logger.warning("taskDescription field is in use and will be overwritten \(identifier, privacy: .public)")
			}

			task.taskDescription = identifier

			task.resume()
		}
	}
}
