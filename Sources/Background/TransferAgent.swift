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
	public typealias Response = Result<(URL, URLResponse), Error>
	public typealias Handler = (String, Response) -> Void

	public typealias HTTPResponse = Result<(URL, HTTPURLResponse), Error>
	public typealias HTTPHandler = (String, HTTPResponse) -> Void

	private let logger = Logger(subsystem: "com.chimehq.Background", category: "TransferAgent")
	private var downloadHandlers = [String: Handler]()
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

	public var identifierProvider: (URLSessionTask) throws -> String

	public init(configuration: URLSessionConfiguration) {
		self.sessionConfiguration = configuration

		self.identifierProvider = { task in
			guard let id = task.taskDescription else {
				throw TransferAgentError.identifierUnavailable
			}

			return id
		}
	}
}

extension TransferAgent {
	private func sessionDidFinishEvents() {
		sessionCompletionHandler()
		self.pendingEvents = false
	}

	private func taskComplete(_ task: URLSessionTask, _ error: Error?) {
		guard let error = error else { return }

		guard let identifier = try? self.identifierProvider(task) else {
			handleAbandonedTask(task, identifier: nil)
			return
		}

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
}

extension TransferAgent {
	public func beginDownload(
		with request: URLRequest,
		identifier: String,
		configureTask: @escaping (URLSessionDownloadTask) -> Void = { _ in },
		handler: @escaping Handler
	) {
		precondition(downloadHandlers[identifier] == nil)

		downloadHandlers[identifier] = handler

		Task {
			let (_, _, downloadTasks) = await session.tasks
			let ids = Set(downloadTasks.compactMap { try? self.identifierProvider($0) })

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
		handler: @escaping HTTPHandler
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
		guard let identifier = try? self.identifierProvider(downloadTask) else {
			handleAbandonedTask(downloadTask, identifier: nil)

			return
		}

		logger.info("completed download task: \(identifier, privacy: .public)")

		do {
			guard let response = downloadTask.response else {
				throw TransferAgentError.noResponse
			}

			relayDownloadResponse(.success((location, response)), for: identifier, task: downloadTask)
		} catch {
			relayDownloadResponse(.failure(error), for: identifier, task: downloadTask)
		}

		try? FileManager.default.removeItem(at: location)
	}

	private func relayDownloadResponse(_ response: Response, for identifier: String, task: URLSessionTask) {
		guard let handler = downloadHandlers[identifier] else {
			self.handleAbandonedTask(task, identifier: identifier)
			return
		}

		handler(identifier, response)
	}
}
