import Foundation

/// Intermediate object to use an actor type as a URLSessionDelegate
final class URLSessionDelegateAdapter: NSObject {
	enum Event: Sendable {
		case didFinishEvents
		case taskComplete(URLSessionTask, Error?)
		case downloadFinished(URLSessionDownloadTask, URL)
	}

	private let streamPair = AsyncStream<Event>.makeStream()

	public var eventStream: AsyncStream<Event> {
		streamPair.0
	}
}

extension URLSessionDelegateAdapter: URLSessionDelegate {
	func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
		streamPair.1.yield(.didFinishEvents)
	}
}

extension URLSessionDelegateAdapter: URLSessionTaskDelegate {
	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		streamPair.1.yield(.taskComplete(task, error))
	}
}

extension URLSessionDelegateAdapter: URLSessionDownloadDelegate {
	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
		streamPair.1.yield(.downloadFinished(downloadTask, location))
	}
}

extension URLSession {
    var tasksWhenAvailable: ([URLSessionDataTask], [URLSessionUploadTask], [URLSessionDownloadTask]) {
        get async {
            // force a turn of the main runloop, which I have found to sometimes be necessary for this to actually work
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async {
                    continuation.resume()
                }
            }

            return await tasks
        }
    }
}
