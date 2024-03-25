import Foundation
import OSLog

/// Manages background downloads
public actor Downloader {
    public typealias Identifier = String
    public typealias Handler = @Sendable (Identifier, Result<(URL, URLResponse), Error>) -> Void

    private let session: URLSession
    private var handlers = [Identifier: Handler]()
    private let logger = Logger(subsystem: "com.chimehq.Background", category: "Uploader")
    private let taskInterface: BackgroundTaskConfiguration
	private var pendingEvents = true
	private var sessionCompletionHandler: () -> Void = {}

    public init(
        sessionConfiguration: URLSessionConfiguration,
        taskConfiguration: BackgroundTaskConfiguration = BackgroundTaskConfiguration.taskDescriptionCoder
    ) {
        let adapter = URLSessionDelegateAdapter()

        self.taskInterface = taskConfiguration
        self.session = URLSession(configuration: sessionConfiguration, delegate: adapter, delegateQueue: nil)

        adapter.finishHandler = { [weak self] in
            guard let self else { return }
            
            Task {
                await self.finishedEvents()
            }
        }

        adapter.taskCompletedHandler = { [weak self] task, error in
			guard let self else { return }

            Task {
				await self.taskFinished(task, with: error, url: nil)
            }
        }

		adapter.downloadFinishedHandler = { [weak self] task, url in
			guard let self else { return }

			Task {
				await self.taskFinished(task, with: nil, url: url)
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

    private var activeIdentifiers: Set<String> {
        get async {
            let (_, _, downloadTasks) = await session.tasksWhenAvailable
            let ids = downloadTasks.compactMap { taskInterface.getIdentifier($0) }

            return Set(ids)
        }
    }
}

extension Downloader {
    public func beginDownload(
        of request: URLRequest,
        identifier: String,
        handler: @escaping Handler
    ) {
        precondition(handlers[identifier] == nil)

        handlers[identifier] = handler

        Task {
            let ids = await activeIdentifiers

            if ids.contains(identifier) {
                logger.debug("found existing task for \(identifier, privacy: .public)")
                return
            }

            let task = self.session.downloadTask(with: request)

            taskInterface.prepareTask(task, request, identifier)

            task.resume()
        }
    }

    public func download(
        _ request: URLRequest,
        with identifier: String
    ) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            beginDownload(of: request, identifier: identifier) { _, response in
                continuation.resume(with: response)
            }
        }
    }

	/// Start a download task and return a NetworkResponse when complete.
	public func networkResponse(
		from request: URLRequest,
		with identifier: String
	) async -> NetworkResponse<URL> {
		do {
			let result = try await download(request, with: identifier)

			return NetworkResponse(response: result.1, value: result.0)
		} catch {
			return NetworkResponse(response: nil, error: error, value: nil)
		}
	}
}

extension Downloader {
	private func finishedEvents() async {
		if pendingEvents == false {
			logger.debug("skipping pending events after the first")
			return
		}

		self.pendingEvents = false

		await withCheckedContinuation { continuation in
			self.sessionCompletionHandler = {
				continuation.resume()
			}
		}
	}

	private func taskFinished(_ task: URLSessionTask, with error: Error?, url: URL?) {
		guard task is URLSessionDownloadTask else { return }
		let identifier = taskInterface.getIdentifier(task) ?? "<nil>"

		logger.info("completed download task: \(identifier, privacy: .public)")

		let response = task.responseResult(with: error)

		downloadFinished(with: response, identifier: identifier, location: url)
	}

	private func downloadFinished(with result: Result<URLResponse, Error>, identifier: Identifier, location: URL?) {
		guard let handler = handlers[identifier] else {
			logger.info("no handler found for \(identifier, privacy: .public)")

			return
		}

		switch (result, location) {
		case let (.failure(error), nil):
			handler(identifier, .failure(error))
		case (.success, nil):
			handler(identifier, .failure(NetworkResponseError.expectedContentMissing))
		case let (.success(response), url?):
			handler(identifier, .success((url, response)))

			try? FileManager.default.removeItem(at: url)
		case let (.failure(error), url?):
			handler(identifier, .failure(error))

			try? FileManager.default.removeItem(at: url)
		}
	}

	public nonisolated func handleBackgroundSessionEvents(_ completion: @escaping @Sendable () -> Void) {
		Task {
			await finishedEvents()

			completion()
		}
	}
}
