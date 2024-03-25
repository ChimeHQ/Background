import Foundation

public enum NetworkResponseError: Error {
	case protocolError(Error)
	case noResponseOrError
	case noHTTPResponse(URLResponse)
	case httpReponseInvalid
	case requestInvalid
	case missingOriginalRequest
	case transientFailure(TimeInterval?)
	case expectedContentMissing
}

public enum NetworkResponse<Value>  {
	case failed(NetworkResponseError)
	case rejected
	case retry(HTTPURLResponse)
	case success(Value, HTTPURLResponse)
}

extension NetworkResponse : Sendable where Value : Sendable {}

extension NetworkResponse: CustomStringConvertible {
	public var description: String {
		switch self {
		case .failed(let e): return "failed (\(e))"
		case .rejected: return "rejected"
		case .retry: return "retry"
		case let .success(value, response): return "success (\(response.statusCode)) \(value)"
		}
	}
}

extension NetworkResponse {
	public init(response: URLResponse?, error: Error? = nil, value: Value?) {
		if let e = error {
			self = .failed(NetworkResponseError.protocolError(e))
			return
		}

		guard let response = response else {
			self = .failed(NetworkResponseError.noResponseOrError)
			return
		}

		guard let httpResponse = response as? HTTPURLResponse else {
			self = .failed(NetworkResponseError.noHTTPResponse(response))
			return
		}

		let code = httpResponse.statusCode

		switch code {
		case 0..<200:
			self = NetworkResponse.failed(NetworkResponseError.httpReponseInvalid)
		case 200, 201, 202, 204:
			if let value = value {
				self = .success(value, httpResponse)
			} else {
				self = .failed(NetworkResponseError.expectedContentMissing)
			}
		case 408, 429, 500, 502, 503, 504:
			self = NetworkResponse.retry(httpResponse)
		default:
			self = NetworkResponse.rejected
		}
	}
}

extension NetworkResponse where Value == Void {
	public init(response: URLResponse?, error: Error? = nil) {
		self.init(response: response, error: error, value: ())
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

import Foundation

import Background

let config = URLSessionConfiguration.background(withIdentifier: "com.my.background-id")
let downloader = Downloader(sessionConfiguration: config)

let request = URLRequest(url: URL(string: "https://myurl")!)
let identifier = "some-stable-id-appropriate-for-the-file"

Task<Void, Never> {
	// remember, this await may not return during the processes entire lifecycle!
	let response = await downloader.networkResponse(from: request, with: identifier)

	switch response {
	case .rejected:
		// the server did not like the request
		break
	case let .retry(urlResponse):
		let interval = urlResponse.retryAfterInterval ?? 60.0

		// transient failure, could retry with interval if that makes sense
		break
	case let .failed(error):
		// failed and a retry is unlikely to succeed
		break
	case let .success(url, urlResponse):
		// download completed successfully at url
		break
	}
}
