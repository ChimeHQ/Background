import Foundation

public enum NetworkResponseError: Error {
	case protocolError(Error)
	case noResponseOrError
	case noHTTPResponse(URLResponse)
	case httpReponseInvalid
	case requestInvalid
	case missingOriginalRequest
	case transientFailure(TimeInterval?)
}

public enum NetworkResponse: Sendable {
	case failed(NetworkResponseError)
	case rejected
	case retry(HTTPURLResponse)
	case success(HTTPURLResponse)
}

extension NetworkResponse: CustomStringConvertible {
	public var description: String {
		switch self {
		case .failed(let e): return "failed (\(e))"
		case .rejected: return "rejected"
		case .retry: return "retry"
		case let .success(response): return "success (\(response.statusCode))"
		}
	}
}

extension NetworkResponse {
	public init(response: URLResponse?, error: Error? = nil) {
		if let e = error {
			self = NetworkResponse.failed(NetworkResponseError.protocolError(e))
			return
		}

		guard let response = response else {
			self = NetworkResponse.failed(NetworkResponseError.noResponseOrError)
			return
		}

		guard let httpResponse = response as? HTTPURLResponse else {
			self = NetworkResponse.failed(NetworkResponseError.noHTTPResponse(response))
			return
		}

		let code = httpResponse.statusCode

		switch code {
		case 0..<200:
			self = NetworkResponse.failed(NetworkResponseError.httpReponseInvalid)
		case 200, 201, 202, 204:
			self = NetworkResponse.success(httpResponse)
		case 408, 429, 500, 502, 503, 504:
			self = NetworkResponse.retry(httpResponse)
		default:
			self = NetworkResponse.rejected
		}
	}

	public init(task: URLSessionTask, error: Error? = nil) {
		self.init(response: task.response, error: error)
	}

	public init(with result: Result<URLResponse, Error>) {
		switch result {
		case let .success(response):
			self.init(response: response, error: nil)
		case let .failure(error):
			self.init(response: nil, error: error)
		}
	}
}

extension URLResponse {
	public var httpResponse: HTTPURLResponse {
		get throws {
			guard let httpResp = self as? HTTPURLResponse else {
				throw NetworkResponseError.noHTTPResponse(self)
			}

			return httpResp
		}
	}
}
