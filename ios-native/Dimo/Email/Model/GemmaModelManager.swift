import CryptoKit
import Foundation

enum GemmaModelInstallationState: Hashable, Sendable {
  case notInstalled
  case checking
  case downloading(progress: Double, receivedBytes: Int64, totalBytes: Int64)
  case paused
  case verifying
  case initializing
  case installed(version: String, modelURL: URL)
  case failed(String)
}

enum GemmaModelManagerError: LocalizedError, Sendable {
  case insufficientStorage(required: Int64, available: Int64)
  case downloadAlreadyRunning
  case invalidDownloadedSize(expected: Int64, actual: Int64)
  case digestMismatch
  case stagingFailed(String)
  case installationFailed(String)

  var errorDescription: String? {
    switch self {
    case .insufficientStorage(let required, let available):
      return "Gemma needs \(required) bytes free; only \(available) bytes are available."
    case .downloadAlreadyRunning: return "The Gemma download is already running."
    case .invalidDownloadedSize(let expected, let actual):
      return "The Gemma download size is invalid (expected \(expected), received \(actual))."
    case .digestMismatch: return "The Gemma download failed its SHA-256 verification."
    case .stagingFailed(let message): return "The Gemma download could not be staged: \(message)"
    case .installationFailed(let message): return "Gemma could not be installed: \(message)"
    }
  }
}

enum GemmaModelVerifier {
  static func verify(
    _ url: URL,
    expectedByteCount: Int64,
    expectedSHA256: String,
    fileManager: FileManager = .default
  ) throws {
    let attributes = try fileManager.attributesOfItem(atPath: url.path)
    let actualSize = (attributes[.size] as? NSNumber)?.int64Value ?? -1
    guard actualSize == expectedByteCount else {
      throw GemmaModelManagerError.invalidDownloadedSize(
        expected: expectedByteCount,
        actual: actualSize
      )
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while true {
      try Task.checkCancellation()
      let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
      if chunk.isEmpty { break }
      hasher.update(data: chunk)
    }
    let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
    guard digest.caseInsensitiveCompare(expectedSHA256) == .orderedSame else {
      throw GemmaModelManagerError.digestMismatch
    }
  }
}

private protocol GemmaDownloadEventSink: AnyObject, Sendable {
  func downloadDidProgress(taskIdentifier: Int, received: Int64, expected: Int64) async
  func downloadDidStage(taskIdentifier: Int, at url: URL) async
  func downloadDidFail(taskIdentifier: Int, error: Error, resumeData: Data?) async
}

enum GemmaBackgroundSessionEvents {
  private final class State: @unchecked Sendable {
    let lock = NSLock()
    var completionHandler: (() -> Void)?
    var pendingTaskIdentifiers = Set<Int>()
    var sessionFinished = false
  }

  private static let state = State()

  static func registerCompletion(_ completionHandler: @escaping () -> Void) {
    state.lock.lock()
    state.completionHandler = completionHandler
    let handler = takeReadyHandlerLocked()
    state.lock.unlock()
    handler?()
  }

  static func beginProcessing(taskIdentifier: Int) {
    state.lock.lock()
    state.pendingTaskIdentifiers.insert(taskIdentifier)
    state.lock.unlock()
  }

  static func finishProcessing(taskIdentifier: Int) {
    state.lock.lock()
    state.pendingTaskIdentifiers.remove(taskIdentifier)
    let handler = takeReadyHandlerLocked()
    state.lock.unlock()
    handler?()
  }

  static func sessionDidFinishEvents() {
    state.lock.lock()
    state.sessionFinished = true
    let handler = takeReadyHandlerLocked()
    state.lock.unlock()
    handler?()
  }

  private static func takeReadyHandlerLocked() -> (() -> Void)? {
    guard state.sessionFinished, state.pendingTaskIdentifiers.isEmpty,
          let handler = state.completionHandler else { return nil }
    state.completionHandler = nil
    state.sessionFinished = false
    return handler
  }
}

private final class GemmaDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  weak var sink: (any GemmaDownloadEventSink)?
  private let lock = NSLock()
  private var stagingURLs: [Int: URL] = [:]
  private var fallbackStagingURL: URL?

  func setFallbackStagingURL(_ url: URL) {
    lock.lock()
    fallbackStagingURL = url
    lock.unlock()
  }

  func register(taskIdentifier: Int, stagingURL: URL) {
    lock.lock()
    stagingURLs[taskIdentifier] = stagingURL
    lock.unlock()
  }

  func unregister(taskIdentifier: Int) {
    lock.lock()
    stagingURLs[taskIdentifier] = nil
    lock.unlock()
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    Task {
      await sink?.downloadDidProgress(
        taskIdentifier: downloadTask.taskIdentifier,
        received: totalBytesWritten,
        expected: totalBytesExpectedToWrite
      )
    }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    GemmaBackgroundSessionEvents.sessionDidFinishEvents()
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    GemmaBackgroundSessionEvents.beginProcessing(taskIdentifier: downloadTask.taskIdentifier)
    lock.lock()
    let destination = stagingURLs[downloadTask.taskIdentifier] ?? fallbackStagingURL
    lock.unlock()
    guard let destination else {
      Task {
        await sink?.downloadDidFail(
          taskIdentifier: downloadTask.taskIdentifier,
          error: GemmaModelManagerError.stagingFailed("No staging destination was registered."),
          resumeData: nil
        )
        GemmaBackgroundSessionEvents.finishProcessing(
          taskIdentifier: downloadTask.taskIdentifier
        )
      }
      return
    }
    do {
      let fileManager = FileManager.default
      try fileManager.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      if fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
      }
      // URLSession deletes `location` when this callback returns, so make a
      // synchronous durable copy before crossing into the manager actor.
      try fileManager.copyItem(at: location, to: destination)
      try Self.applyDataProtection(to: destination)
      Task {
        await sink?.downloadDidStage(
          taskIdentifier: downloadTask.taskIdentifier,
          at: destination
        )
        GemmaBackgroundSessionEvents.finishProcessing(
          taskIdentifier: downloadTask.taskIdentifier
        )
      }
    } catch {
      Task {
        await sink?.downloadDidFail(
          taskIdentifier: downloadTask.taskIdentifier,
          error: error,
          resumeData: nil
        )
        GemmaBackgroundSessionEvents.finishProcessing(
          taskIdentifier: downloadTask.taskIdentifier
        )
      }
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard let error else { return }
    GemmaBackgroundSessionEvents.beginProcessing(taskIdentifier: task.taskIdentifier)
    let nsError = error as NSError
    let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
    Task {
      await sink?.downloadDidFail(
        taskIdentifier: task.taskIdentifier,
        error: error,
        resumeData: resumeData
      )
      GemmaBackgroundSessionEvents.finishProcessing(taskIdentifier: task.taskIdentifier)
    }
  }

  private static func applyDataProtection(to url: URL) throws {
    try FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: url.path
    )
  }
}

/// Owns download, cryptographic verification, and atomic installation.
/// Installed models are deliberately outside account databases and survive sign-out.
actor GemmaModelManager: GemmaDownloadEventSink {
  typealias ModelInitializer = @Sendable (_ modelURL: URL, _ cacheURL: URL) async throws -> Void

  static let installedModelFileName = "model.gguf"
  private static let legacyInstalledModelFileName = "model.litertlm"

  nonisolated let manifest: GemmaModelManifest

  private let rootURL: URL
  private let fileManager: FileManager
  private let delegate = GemmaDownloadDelegate()
  private var currentTask: URLSessionDownloadTask?
  private var intentionallyStoppedTaskIds = Set<Int>()
  private var stagedTaskIds = Set<Int>()
  private var installationInProgress = false
  private var restoreInProgress = false
  private var observers: [UUID: AsyncStream<GemmaModelInstallationState>.Continuation] = [:]
  private(set) var state: GemmaModelInstallationState = .notInstalled

  private lazy var session: URLSession = {
    let configuration = URLSessionConfiguration.background(
      withIdentifier: manifest.backgroundSessionIdentifier
    )
    configuration.sessionSendsLaunchEvents = true
    configuration.isDiscretionary = false
    configuration.waitsForConnectivity = true
    delegate.sink = self
    return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
  }()

  init(
    manifest: GemmaModelManifest,
    rootURL: URL? = nil,
    fileManager: FileManager = .default,
    modelInitializer: @escaping ModelInitializer = { _, _ in }
  ) {
    self.manifest = manifest
    self.fileManager = fileManager
    let resolvedRootURL = rootURL
      ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "Dimo/Models", directoryHint: .isDirectory)
    self.rootURL = resolvedRootURL
    delegate.setFallbackStagingURL(
      resolvedRootURL
        .appending(path: ".staging", directoryHint: .isDirectory)
        .appending(path: manifest.familyDirectoryName, directoryHint: .isDirectory)
        .appending(path: "model.download")
    )
  }

  func observeState() -> AsyncStream<GemmaModelInstallationState> {
    let id = UUID()
    return AsyncStream { continuation in
      observers[id] = continuation
      continuation.yield(state)
      continuation.onTermination = { [weak self] _ in
        Task { await self?.removeObserver(id) }
      }
    }
  }

  func refreshState() async {
    setState(.checking)
    try? removeLegacyLiteRTInstalls()
    let modelURL = installedModelURL
    guard fileManager.fileExists(atPath: modelURL.path),
          fileSize(at: modelURL) == manifest.exactByteCount else {
      setState(.notInstalled)
      return
    }
    setState(.installed(version: manifest.version, modelURL: modelURL))
  }

  func startDownload(allowCellular: Bool) async throws {
    guard currentTask == nil else { throw GemmaModelManagerError.downloadAlreadyRunning }
    try manifest.validate()
    try prepareDirectories()
    try requireFreeStorage()
    try? fileManager.removeItem(at: resumeDataURL)
    var request = URLRequest(url: manifest.downloadURL)
    request.allowsCellularAccess = allowCellular
    request.timeoutInterval = 120
    let task = session.downloadTask(with: request)
    begin(task)
  }

  func pauseDownload() async {
    guard let task = currentTask else { return }
    intentionallyStoppedTaskIds.insert(task.taskIdentifier)
    currentTask = nil
    let resumeData = await task.cancelByProducingResumeData()
    saveResumeData(resumeData)
    setState(.paused)
  }

  func retryDownload(allowCellular: Bool) async throws {
    guard currentTask == nil else { throw GemmaModelManagerError.downloadAlreadyRunning }
    try prepareDirectories()
    try requireFreeStorage()
    let task: URLSessionDownloadTask
    if !allowCellular,
       let resumeData = try? Data(contentsOf: resumeDataURL), !resumeData.isEmpty {
      task = session.downloadTask(withResumeData: resumeData)
    } else {
      if allowCellular { try? fileManager.removeItem(at: resumeDataURL) }
      var request = URLRequest(url: manifest.downloadURL)
      request.allowsCellularAccess = allowCellular
      request.timeoutInterval = 120
      task = session.downloadTask(with: request)
    }
    begin(task)
  }

  func cancelDownload() {
    if let task = currentTask {
      intentionallyStoppedTaskIds.insert(task.taskIdentifier)
      task.cancel()
      delegate.unregister(taskIdentifier: task.taskIdentifier)
    }
    currentTask = nil
    try? fileManager.removeItem(at: resumeDataURL)
    try? fileManager.removeItem(at: stagedDownloadURL)
    setState(fileManager.fileExists(atPath: installedModelURL.path)
      ? .installed(version: manifest.version, modelURL: installedModelURL)
      : .notInstalled)
  }

  func deleteDownloadedModel() throws {
    cancelDownload()
    let family = modelFamilyURL
    if fileManager.fileExists(atPath: family.path) { try fileManager.removeItem(at: family) }
    setState(.notInstalled)
  }

  func restoreBackgroundDownload() async {
    guard !restoreInProgress else { return }
    restoreInProgress = true
    defer { restoreInProgress = false }
    try? prepareDirectories()
    let tasks = await session.allTasks
    guard !installationInProgress else { return }
    switch state {
    case .verifying, .initializing, .installed, .failed:
      return
    default:
      break
    }
    guard let task = tasks.compactMap({ $0 as? URLSessionDownloadTask }).first else {
      if fileManager.fileExists(atPath: stagedDownloadURL.path) {
        await installStagedDownload(at: stagedDownloadURL)
        return
      }
      await refreshState()
      return
    }
    guard !stagedTaskIds.contains(task.taskIdentifier) else { return }
    currentTask = task
    delegate.register(taskIdentifier: task.taskIdentifier, stagingURL: stagedDownloadURL)
    let expected = manifest.exactByteCount
    let received = task.countOfBytesReceived
    setState(.downloading(
      progress: expected > 0 ? min(1, Double(received) / Double(expected)) : 0,
      receivedBytes: received,
      totalBytes: expected
    ))
  }

  func installedURLs() -> (model: URL, cache: URL)? {
    guard fileManager.fileExists(atPath: installedModelURL.path) else { return nil }
    return (installedModelURL, installedCacheURL)
  }

  func downloadDidProgress(taskIdentifier: Int, received: Int64, expected: Int64) {
    guard currentTask?.taskIdentifier == taskIdentifier else { return }
    let total = expected > 0 ? expected : manifest.exactByteCount
    setState(.downloading(
      progress: total > 0 ? min(1, Double(received) / Double(total)) : 0,
      receivedBytes: received,
      totalBytes: total
    ))
  }

  func downloadDidStage(taskIdentifier: Int, at url: URL) async {
    if let currentTask, currentTask.taskIdentifier != taskIdentifier { return }
    stagedTaskIds.insert(taskIdentifier)
    currentTask = nil
    delegate.unregister(taskIdentifier: taskIdentifier)
    try? fileManager.removeItem(at: resumeDataURL)
    await installStagedDownload(at: url)
    stagedTaskIds.remove(taskIdentifier)
  }

  private func installStagedDownload(at url: URL) async {
    guard !installationInProgress else { return }
    installationInProgress = true
    defer { installationInProgress = false }
    do {
      setState(.verifying)
      try verify(url)
      let candidateDirectory = modelFamilyURL.appending(
        path: ".candidate-\(UUID().uuidString)",
        directoryHint: .isDirectory
      )
      let candidateModel = candidateDirectory.appending(path: Self.installedModelFileName)
      let candidateCache = candidateDirectory.appending(path: "cache", directoryHint: .isDirectory)
      try fileManager.createDirectory(at: candidateDirectory, withIntermediateDirectories: true)
      try fileManager.moveItem(at: url, to: candidateModel)
      try fileManager.createDirectory(at: candidateCache, withIntermediateDirectories: true)
      try applyDataProtectionRecursively(at: candidateDirectory)

      let destination = installedVersionURL
      if fileManager.fileExists(atPath: destination.path) {
        _ = try fileManager.replaceItemAt(
          destination,
          withItemAt: candidateDirectory,
          backupItemName: nil,
          options: []
        )
      } else {
        try fileManager.moveItem(at: candidateDirectory, to: destination)
      }
      try removeObsoleteVersions(except: manifest.version)
      try removeLegacyLiteRTInstalls()
      setState(.installed(version: manifest.version, modelURL: installedModelURL))
    } catch {
      try? fileManager.removeItem(at: url)
      setState(.failed(error.localizedDescription))
    }
  }

  func downloadDidFail(taskIdentifier: Int, error: Error, resumeData: Data?) async {
    if stagedTaskIds.remove(taskIdentifier) != nil { return }
    if intentionallyStoppedTaskIds.remove(taskIdentifier) != nil {
      if let resumeData { saveResumeData(resumeData) }
      return
    }
    if let currentTask, currentTask.taskIdentifier != taskIdentifier { return }
    currentTask = nil
    delegate.unregister(taskIdentifier: taskIdentifier)
    if let resumeData { saveResumeData(resumeData) }
    setState(.failed(error.localizedDescription))
  }

  private func begin(_ task: URLSessionDownloadTask) {
    currentTask = task
    delegate.register(taskIdentifier: task.taskIdentifier, stagingURL: stagedDownloadURL)
    setState(.downloading(
      progress: 0,
      receivedBytes: 0,
      totalBytes: manifest.exactByteCount
    ))
    task.resume()
  }

  private func requireFreeStorage() throws {
    let values = try rootURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    let available = values.volumeAvailableCapacityForImportantUsage ?? 0
    let required = max(manifest.minimumFreeStorageBytes, manifest.exactByteCount * 2)
    guard available >= required else {
      throw GemmaModelManagerError.insufficientStorage(required: required, available: available)
    }
  }

  private func verify(_ url: URL) throws {
    try GemmaModelVerifier.verify(
      url,
      expectedByteCount: manifest.exactByteCount,
      expectedSHA256: manifest.sha256,
      fileManager: fileManager
    )
  }

  private func prepareDirectories() throws {
    try fileManager.createDirectory(at: stagingDirectoryURL, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: modelFamilyURL, withIntermediateDirectories: true)
    try removeAbandonedCandidates()
    try applyDataProtectionRecursively(at: rootURL)
  }

  private func removeAbandonedCandidates() throws {
    let children = try fileManager.contentsOfDirectory(
      at: modelFamilyURL,
      includingPropertiesForKeys: nil
    )
    for child in children where child.lastPathComponent.hasPrefix(".candidate-") {
      try fileManager.removeItem(at: child)
    }
  }

  private func applyDataProtectionRecursively(at root: URL) throws {
    try fileManager.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: root.path
    )
    if let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) {
      for case let child as URL in enumerator {
        try fileManager.setAttributes(
          [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
          ofItemAtPath: child.path
        )
      }
    }
  }

  private func removeObsoleteVersions(except retainedVersion: String) throws {
    let children = try fileManager.contentsOfDirectory(
      at: modelFamilyURL,
      includingPropertiesForKeys: nil
    )
    for child in children {
      let name = child.lastPathComponent
      if name != retainedVersion && !name.hasPrefix(".") {
        try fileManager.removeItem(at: child)
      }
    }
  }

  /// Removes LiteRT `.litertlm` installs left from previous app versions so they
  /// cannot be mistaken for the current GGUF artifact.
  private func removeLegacyLiteRTInstalls() throws {
    guard fileManager.fileExists(atPath: modelFamilyURL.path) else { return }
    let children = try fileManager.contentsOfDirectory(
      at: modelFamilyURL,
      includingPropertiesForKeys: nil
    )
    for child in children {
      let legacyModel = child.appending(path: Self.legacyInstalledModelFileName)
      let ggufModel = child.appending(path: Self.installedModelFileName)
      if fileManager.fileExists(atPath: legacyModel.path),
         !fileManager.fileExists(atPath: ggufModel.path) {
        try fileManager.removeItem(at: child)
      }
    }
  }

  private func saveResumeData(_ data: Data?) {
    guard let data, !data.isEmpty else { return }
    try? data.write(to: resumeDataURL, options: .atomic)
    try? fileManager.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: resumeDataURL.path
    )
  }

  private func fileSize(at url: URL) -> Int64 {
    let attributes = try? fileManager.attributesOfItem(atPath: url.path)
    return (attributes?[.size] as? NSNumber)?.int64Value ?? -1
  }

  private func setState(_ newState: GemmaModelInstallationState) {
    state = newState
    for observer in observers.values { observer.yield(newState) }
  }

  private func removeObserver(_ id: UUID) {
    observers[id] = nil
  }

  private var modelFamilyURL: URL {
    rootURL.appending(path: manifest.familyDirectoryName, directoryHint: .isDirectory)
  }

  private var installedVersionURL: URL {
    modelFamilyURL.appending(path: manifest.version, directoryHint: .isDirectory)
  }

  private var installedModelURL: URL {
    installedVersionURL.appending(path: Self.installedModelFileName)
  }

  private var installedCacheURL: URL {
    installedVersionURL.appending(path: "cache", directoryHint: .isDirectory)
  }

  private var stagingDirectoryURL: URL {
    rootURL
      .appending(path: ".staging", directoryHint: .isDirectory)
      .appending(path: manifest.familyDirectoryName, directoryHint: .isDirectory)
  }

  private var stagedDownloadURL: URL {
    stagingDirectoryURL.appending(path: "model.download")
  }

  private var resumeDataURL: URL {
    stagingDirectoryURL.appending(path: "model.resume")
  }
}

struct GemmaModelServices: Sendable {
  let manifests: [EmailGemmaModelVariant: GemmaModelManifest]
  let managers: [EmailGemmaModelVariant: GemmaModelManager]

  func manifest(for variant: EmailGemmaModelVariant) -> GemmaModelManifest? {
    manifests[variant]
  }

  func manager(for variant: EmailGemmaModelVariant) -> GemmaModelManager? {
    managers[variant]
  }

  func manager(forBackgroundSessionIdentifier identifier: String) -> GemmaModelManager? {
    guard let variant = manifests.first(where: {
      $0.value.backgroundSessionIdentifier == identifier
    })?.key else {
      return nil
    }
    return managers[variant]
  }
}

/// Process-wide owners of the per-variant background URLSessions. The app
/// delegate can recreate them before authentication finishes, and the signed-in
/// Email controller then observes the same managers.
enum GemmaModelServicesProvider {
  private final class State: @unchecked Sendable {
    let lock = NSLock()
    var services: GemmaModelServices?
  }

  private static let state = State()

  static func shared() -> GemmaModelServices? {
    state.lock.lock()
    if let services = state.services {
      state.lock.unlock()
      return services
    }
    state.lock.unlock()

    guard let manifests = try? GemmaModelManifest.loadAll() else { return nil }
    var managers: [EmailGemmaModelVariant: GemmaModelManager] = [:]
    for (variant, manifest) in manifests {
      managers[variant] = GemmaModelManager(manifest: manifest)
    }
    let candidate = GemmaModelServices(manifests: manifests, managers: managers)

    state.lock.lock()
    if let existing = state.services {
      state.lock.unlock()
      return existing
    }
    state.services = candidate
    state.lock.unlock()
    return candidate
  }
}
