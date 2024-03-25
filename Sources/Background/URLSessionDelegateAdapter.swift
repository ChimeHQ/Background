import Foundation

/// Intermediate object to use an actor type as a URLSessionDelegate
final class URLSessionDelegateAdapter: NSObject {
    typealias TaskCompletionHandler = (URLSessionTask, Error?) -> Void

	var finishHandler: () -> Void = {}
	var taskCompletedHandler: TaskCompletionHandler = { _, _ in }
	var downloadFinishedHandler: (URLSessionDownloadTask, URL) -> Void = {_, _ in }
}

extension URLSessionDelegateAdapter: URLSessionDelegate {
	func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
		finishHandler()
	}
}

extension URLSessionDelegateAdapter: URLSessionTaskDelegate {
	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		taskCompletedHandler(task, error)
	}
}

extension URLSessionDelegateAdapter: URLSessionDownloadDelegate {
	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
		downloadFinishedHandler(downloadTask, location)
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
