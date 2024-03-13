# Background
Background Tasks and Networking

## Integration

```swift
dependencies: [
    .package(url: "https://github.com/ChimeHQ/Background", branch: "main")
]
```

## Concept

URLSession's background upload and download facilities are relatively straightforward to get started with. But, they are surprisingly difficult to manage. The core challange is an operation could start and/or complete while your process isn't even running. You cannot just wait for a completion handler or `await` call, because they might never happen. This usually means you have to involve peristent storage to juggle state across process launches.

You also typically need to make use of system-provided API to reconnect your session to any work that has happened between launches. This can be done a few different ways, depending on your type of project and how you'd like your system to work.

- [`WidgetConfiguration.onBackgroundSessionEvents(matching:_:)`](https://developer.apple.com/documentation/swiftui/widgetconfiguration/onbackgroundurlsessionevents(matching:_:)-2e152)
- [`UIApplicationDelegate.application(_:handleEventsForBackgroundURLSession:completionHandler:)`](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1622941-application)

Because persistent state is involved and networking operations might already be in-progress, `Uploader` and `Downloader` support restarting operations on start. When your process starts up, you should restart any operations. They will take care of determining if the operations need to be actually started or just reconnected to existing work.

## Usage

Uploading files:

```swift
import Foundation

import Background

let config = URLSessionConfiguration.background(withIdentifier: "com.my.background-id")
let uploader = Uploader(sessionConfiguration: config)

let request = URLRequest(url: URL(string: "https://myurl")!)
let url = URL(fileURLWithPath: "path/to/file")
let identifier = "some-stable-id-appropriate-for-the-file"

Task<Void, Never> {
    // remember, this await may not return during the processes entire lifecycle!
    let response = await uploader.networkResponse(from: request, uploading: url, with: identifier)
    
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
    case let .success(urlResponse):
        // upload completed successfully
        break
    }
}
```

## Contributing and Collaboration

I'd love to hear from you! Get in touch via an issue or pull request.

I prefer collaboration, and would love to find ways to work together if you have a similar project.

I prefer indentation with tabs for improved accessibility. But, I'd rather you use the system you want and make a PR than hesitate because of whitespace.

By participating in this project you agree to abide by the [Contributor Code of Conduct](CODE_OF_CONDUCT.md).
