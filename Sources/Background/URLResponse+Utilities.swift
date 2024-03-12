import Foundation

extension HTTPURLResponse {
	/// Returns the Retry-After HTTP header as a TimeInterval, if present
	public var retryAfterInterval: TimeInterval? {
		allHeaderFields["Retry-After"]
			.flatMap { $0 as? String }
			.flatMap { Int($0) }
			.map { TimeInterval($0) }
	}
}

extension URLSessionTask {
	/// Returns the task's response Retry-After HTTP header as a TimeInterval, if present
	public var retryAfterInterval: TimeInterval? {
		guard let response else {
			return nil
		}

		guard let httpResponse = response as? HTTPURLResponse else {
			return nil
		}

		return httpResponse.retryAfterInterval
	}

	func responseResult(with error: Error?) -> Result<URLResponse, Error> {
		switch (response, error) {
		case let (_, error?):
			.failure(error)
		case let (urlResponse?, nil):
			.success(urlResponse)
		case (nil, nil):
			.failure(NetworkResponseError.noResponseOrError)
		}
	}
}
