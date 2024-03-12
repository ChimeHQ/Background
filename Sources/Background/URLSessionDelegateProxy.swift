import Foundation

/// Intermediate object to use an actor type as a URLSessionDelegate
final class URLSessionDelegateProxy: NSObject {
	var finishHandler: () -> Void = {}
	var taskCompletedHandler: (URLSessionTask, Error?) -> Void = { _, _ in }
	var downloadFinishedHandler: (URLSessionDownloadTask, URL) -> Void = {_, _ in }
}

extension URLSessionDelegateProxy: URLSessionDelegate {
	func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
		finishHandler()
	}
}

extension URLSessionDelegateProxy: URLSessionTaskDelegate {
	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		taskCompletedHandler(task, error)
	}
}

extension URLSessionDelegateProxy: URLSessionDownloadDelegate {
	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
		downloadFinishedHandler(downloadTask, location)
	}
}
