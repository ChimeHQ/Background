# Background
Background Tasks and Networking

## Integration

```swift
dependencies: [
    .package(url: "https://github.com/ChimeHQ/Background", branch: "Main")
]
```

## Usage

Uploading files:

```swift
import Foundation

import Background

let config = URLSessionConfiguration.background(withIdentifier: "com.my.background-id")
let uploader = Uploader(
    sessionConfiguration: config,
    identifierProvider: { task in 
        task.taskDescriptor
    }
)

```

Downloading data:

```swift
```

## Contributing and Collaboration

I'd love to hear from you! Get in touch via an issue or pull request.

I prefer collaboration, and would love to find ways to work together if you have a similar project.

I prefer indentation with tabs for improved accessibility. But, I'd rather you use the system you want and make a PR than hesitate because of whitespace.

By participating in this project you agree to abide by the [Contributor Code of Conduct](CODE_OF_CONDUCT.md).
