import XCTest
import Background

final class HTTPHeaderTests: XCTestCase {
	func testRetryAfter() throws {
		let response = HTTPURLResponse(url: URL(string: "http://example.com")!,
									  statusCode: 200,
									  httpVersion: "1.1",
									  headerFields: ["Retry-After": "120"])

		XCTAssertEqual(response?.retryAfterInterval, 120.0)
	}
}
