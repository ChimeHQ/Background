<div align="center">

[![Build Status][build status badge]][build status]
[![Platforms][platforms badge]][platforms]
[![Documentation][documentation badge]][documentation]
[![Matrix][matrix badge]][matrix]

</div>

# Background
Background Tasks and Networking

## Integration

```swift
dependencies: [
    .package(url: "https://github.com/ChimeHQ/Background", branch: "main")
]
```

## Concept

[`URLSession`](https://developer.apple.com/documentation/foundation/urlsession)'s background upload and download facilities are relatively straightforward to get started with. But, they are surprisingly difficult to manage. The core challange is an operation could start and/or complete while your process isn't even running. You cannot just wait for a completion handler or `await` call. This usually means you have to involve peristent storage to juggle state across process launches.

You also typically need to make use of system-provided API to reconnect your session to any work that has happened between launches. This can be done a few different ways, depending on your type of project and how you'd like your system to work.

- [`WidgetConfiguration.onBackgroundSessionEvents(matching:_:)`](https://developer.apple.com/documentation/swiftui/widgetconfiguration/onbackgroundurlsessionevents(matching:_:)-2e152)
- [`UIApplicationDelegate.application(_:handleEventsForBackgroundURLSession:completionHandler:)`](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1622941-application)

Because persistent state is involved and networking operations might already be in-progress, the `Uploader` and `Downloader` types support restarting operations. Your job is to track that in-flight work. You can then just restart any work that hasn't yet completed on launch using the `Uploader` or `Downloader` types. They will take care of determining if the operations need to be actually started or just reconnected to existing work.

## Usage

### Uploading

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

### Downloading

```swift
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
```

### Widget Support

If you are making use of `Downloader` in a widget, you must reconnect the session as part of your `WidgetConfiguration`. Here's how:

```swift
struct YourWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: provider) { entry in
           YourWidgetView()
        }
        .onBackgroundURLSessionEvents { identifier, completion in
            // find/create your downloader instance using the system-supplied
            // identifier
            let downloader = lookupDownloader(with: identifier)
            
            // and allow it to handle the events, possibly resulting in
            // callbacks and/or async functions completing
            downloader.handleBackgroundSessionEvents(completion)
        }
    }
}
```

### More Complex Usage

This package is used to manage the background uploading facilities of [Wells](https://github.com/ChimeHQ/Wells), a diagnostics report submission system. You can check out that project for a much more complex example of how to manage background uploads.

## Contributing and Collaboration

I would love to hear from you! Issues or pull requests work great. Both a [Matrix space][matrix] and [Discord][discord] are available for live help, but I have a strong bias towards answering in the form of documentation. You can also find me on [the web](https://www.massicotte.org).

I prefer collaboration, and would love to find ways to work together if you have a similar project.

I prefer indentation with tabs for improved accessibility. But, I'd rather you use the system you want and make a PR than hesitate because of whitespace.

By participating in this project you agree to abide by the [Contributor Code of Conduct](CODE_OF_CONDUCT.md).

[build status]: https://github.com/ChimeHQ/Background/actions
[build status badge]: https://github.com/ChimeHQ/Background/workflows/CI/badge.svg
[platforms]: https://swiftpackageindex.com/ChimeHQ/Background
[platforms badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FChimeHQ%2FBackground%2Fbadge%3Ftype%3Dplatforms
[documentation]: https://swiftpackageindex.com/ChimeHQ/Background/main/documentation
[documentation badge]: https://img.shields.io/badge/Documentation-DocC-blue
[matrix]: https://matrix.to/#/%23chimehq%3Amatrix.org
[matrix badge]: https://img.shields.io/matrix/chimehq%3Amatrix.org?label=Matrix
[discord]: https://discord.gg/esFpX6sErJ
