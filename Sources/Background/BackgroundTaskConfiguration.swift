import Foundation

/// Interface to long-running URLSessionTask objects.
public struct BackgroundTaskConfiguration: Sendable {
    public typealias IdentifierProvider = @Sendable (URLSessionTask) -> String?
    public typealias PrepareTask = @Sendable (URLSessionTask, URLRequest, String) -> Void

    public let getIdentifier: IdentifierProvider
    public let prepareTask: PrepareTask

    public init(
        getIdentifier: @escaping IdentifierProvider,
        prepareTask: @escaping PrepareTask = { _, _, _ in }
    ) {
        self.getIdentifier = getIdentifier
        self.prepareTask = prepareTask
    }

    /// Stores a persistent identifier within the `URLSessionTask`'s `taskDescription` property.
    public static let taskDescriptionCoder = BackgroundTaskConfiguration(
        getIdentifier: { $0.taskDescription },
        prepareTask: { $0.taskDescription = $2 }
    )
}
