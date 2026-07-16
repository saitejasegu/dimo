import Foundation
import OSLog

#if canImport(LiteRTLM)
import LiteRTLM
#endif

private let emailGemmaLogger = Logger(
  subsystem: "app.dimo.ios",
  category: "EmailGemma"
)

enum EmailGemmaPacing {
  static let normalMinimumStartInterval: Duration = .seconds(6)
  static let warmMinimumStartInterval: Duration = .seconds(60)

  static func minimumStartInterval(
    for thermalState: ProcessInfo.ThermalState
  ) -> Duration {
    switch thermalState {
    case .nominal:
      return normalMinimumStartInterval
    case .fair, .serious, .critical:
      return warmMinimumStartInterval
    @unknown default:
      return warmMinimumStartInterval
    }
  }
}

enum EmailOpenRouterPacing {
  /// OpenRouter can run faster than the on-device model without heating the phone.
  /// Three seconds keeps requests sequential while allowing up to 20 starts per minute.
  static let minimumStartInterval: Duration = .seconds(3)
}

/// Reserves process-wide start times for one analyzer across every analysis path.
/// Reserving before sleeping prevents concurrent refresh and upgrade work from
/// beginning two requests after the same delay.
actor EmailAnalysisStartThrottle {
  static let gemma = EmailAnalysisStartThrottle()
  static let openRouter = EmailAnalysisStartThrottle()

  private let clock = ContinuousClock()
  private var nextStart: ContinuousClock.Instant?

  func waitForNextStart(minimumInterval: Duration) async throws {
    let now = clock.now
    let scheduledStart: ContinuousClock.Instant
    if let nextStart, nextStart > now {
      scheduledStart = nextStart
    } else {
      scheduledStart = now
    }
    nextStart = scheduledStart.advanced(by: minimumInterval)

    if scheduledStart > now {
      try await clock.sleep(until: scheduledStart, tolerance: .seconds(1))
    }
    try Task.checkCancellation()
  }
}

protocol EmailTextGenerationRuntime: Sendable {
  func load() async throws
  func generate(prompt: String, maximumOutputTokens: Int) async throws -> String
  func unload() async
}

enum EmailGemmaResponseText {
  static func select(content: String, channels: [String: String]) -> String {
    let preferredChannelNames = ["final", "answer", "content", "response"]
    var candidates: [String] = preferredChannelNames.compactMap { preferredName in
      channels.first { $0.key.caseInsensitiveCompare(preferredName) == .orderedSame }?.value
    }
    candidates.append(content)
    candidates.append(contentsOf: channels
      .filter { key, _ in
        !preferredChannelNames.contains { key.caseInsensitiveCompare($0) == .orderedSame }
      }
      .sorted { $0.key < $1.key }
      .map(\.value))

    if let jsonCandidate = candidates.first(where: {
      EmailJSONEnvelopeExtractor.containsCompleteObject($0)
    }) {
      return jsonCandidate
    }
    return candidates.first(where: {
      !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }) ?? ""
  }
}

#if canImport(LiteRTLM)
/// The only Dimo type that knows LiteRT-LM's early-preview Swift API.
actor LiteRTLMEmailRuntime: EmailTextGenerationRuntime {
  enum LoadedBackend: String, Sendable { case gpu, cpu }

  private let modelURL: URL
  private let cacheURL: URL
  private var engine: Engine?
  private(set) var loadedBackend: LoadedBackend?
  private var activeConversation: Conversation?
  private var operationInProgress = false
  private var operationWaiters: [CheckedContinuation<Void, Never>] = []
  private var lifecycleGeneration = 0

  init(modelURL: URL, cacheURL: URL) {
    self.modelURL = modelURL
    self.cacheURL = cacheURL
  }

  func load() async throws {
    try await acquireOperation()
    defer { releaseOperation() }
    guard engine == nil else { return }
    guard FileManager.default.fileExists(atPath: modelURL.path) else {
      throw EmailLanguageModelError.modelNotInstalled
    }
    try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
    let generation = lifecycleGeneration
    do {
      let candidate = try await makeEngine(backend: .gpu)
      try Task.checkCancellation()
      guard generation == lifecycleGeneration else { throw CancellationError() }
      engine = candidate
      loadedBackend = .gpu
    } catch {
      if error is CancellationError { throw error }
      emailGemmaLogger.debug(
        "Gemma GPU initialization failed; retrying on CPU: \(String(describing: error), privacy: .public)"
      )
      do {
        let candidate = try await makeEngine(backend: .cpu())
        try Task.checkCancellation()
        guard generation == lifecycleGeneration else { throw CancellationError() }
        engine = candidate
        loadedBackend = .cpu
      } catch {
        if error is CancellationError { throw error }
        emailGemmaLogger.error(
          "Gemma initialization failed: \(String(describing: error), privacy: .public)"
        )
        throw mapRuntimeError(error, initialization: true)
      }
    }
  }

  func generate(prompt: String, maximumOutputTokens: Int) async throws -> String {
    try await acquireOperation()
    defer {
      activeConversation?.close()
      activeConversation = nil
      releaseOperation()
    }
    guard let engine else { throw EmailLanguageModelError.runtimeUnavailable }
    let generation = lifecycleGeneration
    do {
      let sampler = try SamplerConfig(topK: 1, topP: 1, temperature: 0, seed: 0)
      let config = ConversationConfig(
        samplerConfig: sampler,
        maxOutputTokens: maximumOutputTokens
      )
      // A new conversation guarantees a fresh stateless KV cache per email.
      let conversation = try await engine.createConversation(with: config)
      guard generation == lifecycleGeneration else { throw CancellationError() }
      activeConversation = conversation
      // LiteRT-LM supports only one session per engine. Ending consumption of
      // sendMessageStream early leaves its callback context retaining the
      // native conversation briefly, so the next email can fail with
      // "A session already exists." Await the token-capped response instead;
      // the Conversation is then destroyed before this method returns.
      let response = try await conversation.sendMessage(Message(prompt))
      guard !Task.isCancelled, generation == lifecycleGeneration else {
        throw CancellationError()
      }
      let selectedResponse = EmailGemmaResponseText.select(
        content: response.toString,
        channels: response.channels
      )
      if EmailJSONEnvelopeExtractor.containsCompleteObject(selectedResponse) {
        return selectedResponse
      }
      emailGemmaLogger.notice(
        "Gemma first response contained no JSON object; content characters: \(response.toString.count, privacy: .public); channels: \(response.channels.keys.sorted().joined(separator: ","), privacy: .public); requesting JSON repair"
      )

      // Keep the same conversation: LiteRT-LM permits only one session per
      // engine, and the first turn may contain useful reasoning even though it
      // omitted the structured answer.
      let repairedResponse = try await conversation.sendMessage(
        Message(EmailPromptBuilder.jsonRepairPrompt)
      )
      guard !Task.isCancelled, generation == lifecycleGeneration else {
        throw CancellationError()
      }
      let selectedRepair = EmailGemmaResponseText.select(
        content: repairedResponse.toString,
        channels: repairedResponse.channels
      )
      if !EmailJSONEnvelopeExtractor.containsCompleteObject(selectedRepair) {
        emailGemmaLogger.error(
          "Gemma repair response contained no JSON object; content characters: \(repairedResponse.toString.count, privacy: .public); channels: \(repairedResponse.channels.keys.sorted().joined(separator: ","), privacy: .public)"
        )
      }
      return selectedRepair
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      emailGemmaLogger.error(
        "Gemma generation failed: \(String(describing: error), privacy: .public)"
      )
      throw mapRuntimeError(error, initialization: false)
    }
  }

  func unload() async {
    lifecycleGeneration += 1
    try? activeConversation?.cancel()
    activeConversation?.close()
    activeConversation = nil
    engine = nil
    loadedBackend = nil
  }

  private func acquireOperation() async throws {
    if operationInProgress {
      await withCheckedContinuation { continuation in
        operationWaiters.append(continuation)
      }
      do {
        try Task.checkCancellation()
      } catch {
        releaseOperation()
        throw error
      }
      return
    }
    operationInProgress = true
  }

  private func releaseOperation() {
    if operationWaiters.isEmpty {
      operationInProgress = false
    } else {
      operationWaiters.removeFirst().resume()
    }
  }

  private func makeEngine(backend: Backend) async throws -> Engine {
    let config = try EngineConfig(
      modelPath: modelURL.path,
      backend: backend,
      maxNumTokens: EmailPromptBuilder.runtimeContextTokens,
      cacheDir: cacheURL.path
    )
    let candidate = Engine(engineConfig: config)
    try await candidate.initialize()
    return candidate
  }

  private func mapRuntimeError(_ error: Error, initialization: Bool) -> EmailLanguageModelError {
    let description = String(describing: error)
    let lower = description.lowercased()
    if lower.contains("memory") || lower.contains("allocation") {
      return .outOfMemory
    }
    if lower.contains("unsupported") || lower.contains("not supported") {
      return .unsupportedDevice
    }
    if lower.contains("model") && (lower.contains("invalid") || lower.contains("corrupt")) {
      return .corruptModel
    }
    return initialization
      ? .initializationFailed(description)
      : .generationFailed(description)
  }
}
#else
actor LiteRTLMEmailRuntime: EmailTextGenerationRuntime {
  init(modelURL: URL, cacheURL: URL) {}
  func load() async throws { throw EmailLanguageModelError.runtimeUnavailable }
  func generate(prompt: String, maximumOutputTokens: Int) async throws -> String {
    throw EmailLanguageModelError.runtimeUnavailable
  }
  func unload() async {}
}
#endif

actor GemmaEmailLanguageModel: EmailLanguageModel {
  private let runtime: any EmailTextGenerationRuntime
  private let timeout: Duration
  private var loaded = false

  init(runtime: any EmailTextGenerationRuntime, timeout: Duration = .seconds(60)) {
    self.runtime = runtime
    self.timeout = timeout
  }

  func load() async throws {
    guard !loaded else { return }
    try await runtime.load()
    loaded = true
  }

  func analyze(_ request: EmailAnalysisRequest) async throws -> EmailAnalysisResult {
    guard loaded else { throw EmailLanguageModelError.runtimeUnavailable }
    let prompt = EmailPromptBuilder.build(request)
    let response: String
    do {
      response = try await EmailInferenceRace.run(
        runtime: runtime,
        prompt: prompt,
        timeout: timeout
      )
    } catch let error as EmailLanguageModelError {
      if error.shouldUnloadRuntime { await unload() }
      throw error
    }
    return try EmailStructuredOutputValidator.validate(response: response, request: request)
  }

  func unload() async {
    await runtime.unload()
    loaded = false
  }
}

/// Uses unstructured children so a timeout can return even if the preview
/// runtime takes time to observe cancellation. The runtime is also unloaded,
/// which synchronously cancels its active LiteRT conversation.
private final class EmailInferenceRace: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<String, Error>?
  private var tasks: [Task<Void, Never>] = []
  private var completed = false

  static func run(
    runtime: any EmailTextGenerationRuntime,
    prompt: String,
    timeout: Duration
  ) async throws -> String {
    let race = EmailInferenceRace()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        race.install(continuation)
        let generation = Task {
          do {
            let value = try await runtime.generate(
              prompt: prompt,
              maximumOutputTokens: EmailPromptBuilder.maximumGeneratedTokens
            )
            race.resolve(.success(value))
          } catch {
            race.resolve(.failure(error))
          }
        }
        let timer = Task {
          do {
            try await Task.sleep(for: timeout)
            race.resolve(.failure(EmailLanguageModelError.timedOut))
            await runtime.unload()
          } catch {
            // The generation task won and cancelled this timer.
          }
        }
        race.setTasks([generation, timer])
      }
    } onCancel: {
      race.resolve(.failure(CancellationError()))
      Task { await runtime.unload() }
    }
  }

  private func install(_ continuation: CheckedContinuation<String, Error>) {
    lock.lock()
    self.continuation = continuation
    lock.unlock()
  }

  private func setTasks(_ tasks: [Task<Void, Never>]) {
    lock.lock()
    if completed {
      lock.unlock()
      tasks.forEach { $0.cancel() }
      return
    }
    self.tasks = tasks
    lock.unlock()
  }

  fileprivate func resolve(_ result: Result<String, Error>) {
    lock.lock()
    guard !completed, let continuation else {
      lock.unlock()
      return
    }
    completed = true
    self.continuation = nil
    let pendingTasks = tasks
    tasks.removeAll()
    lock.unlock()
    pendingTasks.forEach { $0.cancel() }
    continuation.resume(with: result)
  }
}

enum EmailAnalyzerAvailability: String, Sendable {
  case unavailable
  case gemma
}

actor EmailLanguageModelRouter: EmailLanguageModel {
  private let gemma: any EmailLanguageModel
  private var gemmaReady = false
  private var lastGemmaFailureReason: String?

  init(gemma: any EmailLanguageModel) {
    self.gemma = gemma
  }

  func load() async throws {
    do {
      try await gemma.load()
      gemmaReady = true
      lastGemmaFailureReason = nil
    } catch {
      gemmaReady = false
      lastGemmaFailureReason = "Analysis failed"
      emailGemmaLogger.error(
        "Gemma router failed to load: \(String(describing: error), privacy: .public)"
      )
    }
  }

  func analyze(_ request: EmailAnalysisRequest) async throws -> EmailAnalysisResult {
    guard gemmaReady else { throw EmailLanguageModelError.runtimeUnavailable }
    do {
      let result = try await gemma.analyze(request)
      lastGemmaFailureReason = nil
      return result
    } catch let error as EmailLanguageModelError {
      lastGemmaFailureReason = "Analysis failed"
      emailGemmaLogger.error(
        "Gemma analysis failed: \(String(describing: error), privacy: .public)"
      )
      if error.shouldUnloadRuntime {
        await gemma.unload()
        gemmaReady = false
      }
      throw error
    } catch {
      lastGemmaFailureReason = "Analysis failed"
      emailGemmaLogger.error(
        "Gemma analysis failed: \(String(describing: error), privacy: .public)"
      )
      await gemma.unload()
      gemmaReady = false
      throw error
    }
  }

  func unload() async {
    await gemma.unload()
    gemmaReady = false
    lastGemmaFailureReason = nil
  }

  func resourcePressureDidIncrease() async {
    await gemma.unload()
    gemmaReady = false
    lastGemmaFailureReason = "Analysis failed"
  }

  func availability() -> EmailAnalyzerAvailability {
    gemmaReady ? .gemma : .unavailable
  }

  func failureReason() -> String? {
    lastGemmaFailureReason
  }
}
