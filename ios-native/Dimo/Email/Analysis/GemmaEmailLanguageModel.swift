import Foundation
import OSLog

#if canImport(LlamaCpp)
import LlamaCpp
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
  static func select(content: String, channels: [String: String] = [:]) -> String {
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

#if canImport(LlamaCpp)
/// The only Dimo type that knows llama.cpp's C API.
actor LlamaCppEmailRuntime: EmailTextGenerationRuntime {
  enum LoadedBackend: String, Sendable { case metal, cpu }

  private let modelURL: URL
  private let cacheURL: URL
  private let contextTokens: Int
  private static let batchTokenCapacity = 512

  private var model: OpaquePointer?
  private var context: OpaquePointer?
  private var vocab: OpaquePointer?
  private var sampler: UnsafeMutablePointer<llama_sampler>?
  private var batch: llama_batch?
  private var batchCapacity = 0
  private(set) var loadedBackend: LoadedBackend?
  private var operationInProgress = false
  private var operationWaiters: [CheckedContinuation<Void, Never>] = []
  private var lifecycleGeneration = 0
  private var cancelRequested = false

  init(
    modelURL: URL,
    cacheURL: URL,
    contextTokens: Int = EmailPromptBuilder.defaultRuntimeContextTokens
  ) {
    self.modelURL = modelURL
    self.cacheURL = cacheURL
    self.contextTokens = max(2_048, contextTokens)
  }

  func load() async throws {
    try await acquireOperation()
    defer { releaseOperation() }
    guard model == nil else { return }
    guard FileManager.default.fileExists(atPath: modelURL.path) else {
      throw EmailLanguageModelError.modelNotInstalled
    }
    try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
    let generation = lifecycleGeneration
    LlamaCppBackend.shared.ensureInitialized()

    do {
      try loadModel(gpuLayers: -1)
      try Task.checkCancellation()
      guard generation == lifecycleGeneration else { throw CancellationError() }
      loadedBackend = .metal
    } catch {
      if error is CancellationError { throw error }
      emailGemmaLogger.debug(
        "Gemma Metal initialization failed; retrying on CPU: \(String(describing: error), privacy: .public)"
      )
      unloadLocked()
      do {
        try loadModel(gpuLayers: 0)
        try Task.checkCancellation()
        guard generation == lifecycleGeneration else { throw CancellationError() }
        loadedBackend = .cpu
      } catch {
        if error is CancellationError { throw error }
        unloadLocked()
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
      cancelRequested = false
      clearContextMemory()
      releaseOperation()
    }
    guard context != nil, vocab != nil, sampler != nil else {
      throw EmailLanguageModelError.runtimeUnavailable
    }
    let generation = lifecycleGeneration
    cancelRequested = false
    do {
      let templated = try applyChatTemplate(userText: prompt, assistantText: nil)
      var response = try complete(
        prompt: templated,
        maximumOutputTokens: maximumOutputTokens,
        generation: generation
      )
      let selected = EmailGemmaResponseText.select(content: response)
      if EmailJSONEnvelopeExtractor.containsCompleteObject(selected) {
        return selected
      }
      emailGemmaLogger.notice(
        "Gemma first response contained no JSON object; content characters: \(response.count, privacy: .public); requesting JSON repair"
      )
      clearContextMemory()
      let repairPrompt = try applyChatTemplate(
        userText: prompt,
        assistantText: response,
        repairText: EmailPromptBuilder.jsonRepairPrompt
      )
      response = try complete(
        prompt: repairPrompt,
        maximumOutputTokens: maximumOutputTokens,
        generation: generation
      )
      let selectedRepair = EmailGemmaResponseText.select(content: response)
      if !EmailJSONEnvelopeExtractor.containsCompleteObject(selectedRepair) {
        emailGemmaLogger.error(
          "Gemma repair response contained no JSON object; content characters: \(response.count, privacy: .public)"
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
    cancelRequested = true
    // Wait for an in-flight generate to observe cancellation between decode
    // steps. Never free the model while llama_decode may still be running.
    if operationInProgress {
      let released = await waitForOperationRelease(timeout: .seconds(15))
      if !released {
        emailGemmaLogger.error(
          "Gemma unload timed out while an operation was still in progress; deferring teardown"
        )
        return
      }
    }
    unloadLocked()
    while !operationWaiters.isEmpty {
      operationWaiters.removeFirst().resume()
    }
    operationInProgress = false
    cancelRequested = false
  }

  private func waitForOperationRelease(timeout: Duration) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while operationInProgress {
      if ContinuousClock.now >= deadline { return false }
      try? await Task.sleep(for: .milliseconds(50))
    }
    return true
  }

  private func loadModel(gpuLayers: Int32) throws {
#if targetEnvironment(simulator)
    let resolvedGPULayers: Int32 = 0
#else
    let resolvedGPULayers = gpuLayers
#endif
    var modelParams = llama_model_default_params()
    modelParams.n_gpu_layers = resolvedGPULayers
    modelParams.use_mmap = true

    guard let loadedModel = llama_model_load_from_file(modelURL.path, modelParams) else {
      throw EmailLanguageModelError.initializationFailed("llama_model_load_from_file returned nil")
    }

    let nThreads = Int32(max(1, min(8, ProcessInfo.processInfo.processorCount - 1)))
    var contextParams = llama_context_default_params()
    contextParams.n_ctx = UInt32(contextTokens)
    contextParams.n_batch = UInt32(Self.batchTokenCapacity)
    contextParams.n_ubatch = UInt32(Self.batchTokenCapacity)
    contextParams.n_threads = nThreads
    contextParams.n_threads_batch = nThreads

    guard let loadedContext = llama_init_from_model(loadedModel, contextParams) else {
      llama_model_free(loadedModel)
      throw EmailLanguageModelError.initializationFailed("llama_init_from_model returned nil")
    }
    guard let loadedVocab = llama_model_get_vocab(loadedModel) else {
      llama_free(loadedContext)
      llama_model_free(loadedModel)
      throw EmailLanguageModelError.initializationFailed("llama_model_get_vocab returned nil")
    }

    let sparams = llama_sampler_chain_default_params()
    guard let loadedSampler = llama_sampler_chain_init(sparams) else {
      llama_free(loadedContext)
      llama_model_free(loadedModel)
      throw EmailLanguageModelError.initializationFailed("llama_sampler_chain_init returned nil")
    }
    llama_sampler_chain_add(loadedSampler, llama_sampler_init_greedy())

    model = loadedModel
    context = loadedContext
    vocab = loadedVocab
    sampler = loadedSampler
    batch = llama_batch_init(Int32(Self.batchTokenCapacity), 0, 1)
    batchCapacity = Self.batchTokenCapacity
  }

  private func unloadLocked() {
    if let batch {
      llama_batch_free(batch)
      self.batch = nil
    }
    batchCapacity = 0
    if let sampler {
      llama_sampler_free(sampler)
      self.sampler = nil
    }
    if let context {
      llama_free(context)
      self.context = nil
    }
    if let model {
      llama_model_free(model)
      self.model = nil
    }
    vocab = nil
    loadedBackend = nil
  }

  private func clearContextMemory() {
    guard let context else { return }
    llama_memory_clear(llama_get_memory(context), true)
  }

  private func applyChatTemplate(
    userText: String,
    assistantText: String?,
    repairText: String? = nil
  ) throws -> String {
    guard let model else { throw EmailLanguageModelError.runtimeUnavailable }

    var roles: [ContiguousArray<CChar>] = ["user".utf8CString]
    var contents: [ContiguousArray<CChar>] = [userText.utf8CString]
    if let assistantText {
      roles.append("assistant".utf8CString)
      contents.append(assistantText.utf8CString)
    }
    if let repairText {
      roles.append("user".utf8CString)
      contents.append(repairText.utf8CString)
    }

    let tmplPointer = llama_model_chat_template(model, nil)
    return try renderChatTemplate(
      tmpl: tmplPointer,
      roles: roles,
      contents: contents,
      index: 0,
      messages: []
    )
  }

  private func renderChatTemplate(
    tmpl: UnsafePointer<CChar>?,
    roles: [ContiguousArray<CChar>],
    contents: [ContiguousArray<CChar>],
    index: Int,
    messages: [llama_chat_message]
  ) throws -> String {
    if index == roles.count {
      var capacity = max(2 * contents.reduce(0) { $0 + $1.count }, 4_096)
      while true {
        var bytes = [CChar](repeating: 0, count: capacity)
        let written = messages.withUnsafeBufferPointer { buffer in
          llama_chat_apply_template(
            tmpl,
            buffer.baseAddress,
            buffer.count,
            true,
            &bytes,
            Int32(capacity)
          )
        }
        if written < 0 {
          throw EmailLanguageModelError.generationFailed("llama_chat_apply_template failed")
        }
        if Int(written) < capacity {
          return String(cString: bytes)
        }
        capacity = Int(written) + 1
      }
    }

    return try roles[index].withUnsafeBufferPointer { roleBuffer in
      try contents[index].withUnsafeBufferPointer { contentBuffer in
        guard let rolePointer = roleBuffer.baseAddress,
              let contentPointer = contentBuffer.baseAddress else {
          throw EmailLanguageModelError.generationFailed("Chat template message encoding failed")
        }
        var next = messages
        next.append(llama_chat_message(role: rolePointer, content: contentPointer))
        return try renderChatTemplate(
          tmpl: tmpl,
          roles: roles,
          contents: contents,
          index: index + 1,
          messages: next
        )
      }
    }
  }

  private func complete(
    prompt: String,
    maximumOutputTokens: Int,
    generation: Int
  ) throws -> String {
    guard let context, let vocab, let sampler, var batch else {
      throw EmailLanguageModelError.runtimeUnavailable
    }
    guard batchCapacity > 0 else {
      throw EmailLanguageModelError.runtimeUnavailable
    }
    defer { self.batch = batch }

    let tokens = try tokenize(text: prompt, addBos: true)
    guard !tokens.isEmpty else {
      throw EmailLanguageModelError.generationFailed("Prompt tokenization produced no tokens")
    }

    let nCtx = Int(llama_n_ctx(context))
    let maxPromptTokens = nCtx - maximumOutputTokens - 8
    guard tokens.count <= maxPromptTokens else {
      throw EmailLanguageModelError.generationFailed(
        "Prompt is too long for the on-device context (\(tokens.count) tokens)."
      )
    }

    clearContextMemory()
    llama_sampler_reset(sampler)

    // Prefill in chunks that fit the allocated llama_batch capacity. A single
    // oversized prefill previously wrote past seq_id slots and crashed on unwrap.
    var tokenIndex = 0
    while tokenIndex < tokens.count {
      if cancelRequested || Task.isCancelled || generation != lifecycleGeneration {
        throw CancellationError()
      }
      try llama_batch_clear(&batch)
      let chunkEnd = min(tokenIndex + batchCapacity, tokens.count)
      for position in tokenIndex..<chunkEnd {
        try llama_batch_add(
          &batch,
          tokens[position],
          Int32(position),
          [0],
          position == chunkEnd - 1,
          capacity: batchCapacity
        )
      }
      if llama_decode(context, batch) != 0 {
        throw EmailLanguageModelError.generationFailed("llama_decode failed during prefill")
      }
      tokenIndex = chunkEnd
    }

    var nCur = Int32(tokens.count)
    var generated = 0
    var output = ""
    var temporaryInvalid: [CChar] = []

    while generated < maximumOutputTokens {
      if cancelRequested || Task.isCancelled || generation != lifecycleGeneration {
        throw CancellationError()
      }

      let token = llama_sampler_sample(sampler, context, -1)
      llama_sampler_accept(sampler, token)
      if llama_vocab_is_eog(vocab, token) {
        break
      }

      let pieceChars = tokenToPiece(token: token)
      temporaryInvalid.append(contentsOf: pieceChars)
      if let piece = String(validatingUTF8: temporaryInvalid + [0]) {
        temporaryInvalid.removeAll()
        output += piece
      }

      try llama_batch_clear(&batch)
      try llama_batch_add(&batch, token, nCur, [0], true, capacity: batchCapacity)
      nCur += 1
      generated += 1
      if llama_decode(context, batch) != 0 {
        throw EmailLanguageModelError.generationFailed("llama_decode failed during generation")
      }
    }

    if !temporaryInvalid.isEmpty {
      output += String(cString: temporaryInvalid + [0])
    }
    return output
  }

  private func tokenize(text: String, addBos: Bool) throws -> [llama_token] {
    guard let vocab else { throw EmailLanguageModelError.runtimeUnavailable }
    let utf8Count = text.utf8.count
    let capacity = utf8Count + (addBos ? 1 : 0) + 8
    let tokens = UnsafeMutablePointer<llama_token>.allocate(capacity: capacity)
    defer { tokens.deallocate() }
    let count = text.withCString { cString in
      llama_tokenize(
        vocab,
        cString,
        Int32(utf8Count),
        tokens,
        Int32(capacity),
        addBos,
        true
      )
    }
    if count < 0 {
      let needed = Int(-count)
      let larger = UnsafeMutablePointer<llama_token>.allocate(capacity: needed)
      defer { larger.deallocate() }
      let retry = text.withCString { cString in
        llama_tokenize(
          vocab,
          cString,
          Int32(utf8Count),
          larger,
          Int32(needed),
          addBos,
          true
        )
      }
      guard retry > 0 else {
        throw EmailLanguageModelError.generationFailed("llama_tokenize failed")
      }
      return Array(UnsafeBufferPointer(start: larger, count: Int(retry)))
    }
    return Array(UnsafeBufferPointer(start: tokens, count: Int(count)))
  }

  private func tokenToPiece(token: llama_token) -> [CChar] {
    guard let vocab else { return [] }
    var buffer = [CChar](repeating: 0, count: 16)
    let written = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
    if written < 0 {
      let needed = Int(-written)
      var larger = [CChar](repeating: 0, count: needed)
      let retry = llama_token_to_piece(vocab, token, &larger, Int32(needed), 0, false)
      guard retry > 0 else { return [] }
      return Array(larger.prefix(Int(retry)))
    }
    return Array(buffer.prefix(Int(written)))
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

  private func mapRuntimeError(_ error: Error, initialization: Bool) -> EmailLanguageModelError {
    if let modelError = error as? EmailLanguageModelError { return modelError }
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

private final class LlamaCppBackend: @unchecked Sendable {
  static let shared = LlamaCppBackend()
  private let lock = NSLock()
  private var initialized = false

  private init() {}

  func ensureInitialized() {
    lock.lock()
    defer { lock.unlock() }
    guard !initialized else { return }
    llama_backend_init()
    initialized = true
  }
}

private func llama_batch_clear(_ batch: inout llama_batch) throws {
  batch.n_tokens = 0
}

private func llama_batch_add(
  _ batch: inout llama_batch,
  _ id: llama_token,
  _ pos: llama_pos,
  _ seqIds: [llama_seq_id],
  _ logits: Bool,
  capacity: Int
) throws {
  let index = Int(batch.n_tokens)
  guard index < capacity else {
    throw EmailLanguageModelError.generationFailed(
      "llama_batch capacity exceeded (\(index) >= \(capacity))"
    )
  }
  guard let tokenPointer = batch.token,
        let posPointer = batch.pos,
        let nSeqPointer = batch.n_seq_id,
        let seqPointer = batch.seq_id,
        let logitsPointer = batch.logits else {
    throw EmailLanguageModelError.generationFailed("llama_batch buffers are not allocated")
  }
  guard let seqIdsPointer = seqPointer[index] else {
    throw EmailLanguageModelError.generationFailed("llama_batch seq_id slot is nil")
  }
  guard seqIds.count <= 1 else {
    throw EmailLanguageModelError.generationFailed("llama_batch only supports one sequence id")
  }

  tokenPointer[index] = id
  posPointer[index] = pos
  nSeqPointer[index] = Int32(seqIds.count)
  if let seqId = seqIds.first {
    seqIdsPointer[0] = seqId
  }
  logitsPointer[index] = logits ? 1 : 0
  batch.n_tokens += 1
}
#else
actor LlamaCppEmailRuntime: EmailTextGenerationRuntime {
  init(
    modelURL: URL,
    cacheURL: URL,
    contextTokens: Int = EmailPromptBuilder.defaultRuntimeContextTokens
  ) {}
  func load() async throws { throw EmailLanguageModelError.runtimeUnavailable }
  func generate(prompt: String, maximumOutputTokens: Int) async throws -> String {
    throw EmailLanguageModelError.runtimeUnavailable
  }
  func unload() async {}
}
#endif

actor GemmaEmailLanguageModel: EmailLanguageModel {
  private let runtime: any EmailTextGenerationRuntime
  private let contextTokens: Int
  private let timeout: Duration
  private var loaded = false

  init(
    runtime: any EmailTextGenerationRuntime,
    contextTokens: Int = EmailPromptBuilder.defaultRuntimeContextTokens,
    timeout: Duration = .seconds(60)
  ) {
    self.runtime = runtime
    self.contextTokens = max(2_048, contextTokens)
    self.timeout = timeout
  }

  func load() async throws {
    guard !loaded else { return }
    try await runtime.load()
    loaded = true
  }

  func analyze(_ request: EmailAnalysisRequest) async throws -> EmailAnalysisResult {
    guard loaded else { throw EmailLanguageModelError.runtimeUnavailable }
    let prompt = EmailPromptBuilder.build(request, contextTokens: contextTokens)
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
    return try EmailStructuredOutputValidator.validate(
      response: response,
      request: request,
      analyzer: .gemma
    )
  }

  func unload() async {
    await runtime.unload()
    loaded = false
  }
}

/// Uses unstructured children so a timeout can return even if the native
/// runtime takes time to observe cancellation. The runtime is also unloaded,
/// which cancels active llama.cpp generation.
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
            // Cancel generation via resolve; unload happens in analyze() so this
            // timer never deadlocks waiting on the runtime operation lock.
            race.resolve(.failure(EmailLanguageModelError.timedOut))
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
      lastGemmaFailureReason = (error as? LocalizedError)?.errorDescription
        ?? "Local Gemma failed to load."
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
      lastGemmaFailureReason = error.errorDescription ?? "Analysis failed"
      emailGemmaLogger.error(
        "Gemma analysis failed: \(String(describing: error), privacy: .public)"
      )
      if error.shouldUnloadRuntime {
        await gemma.unload()
        gemmaReady = false
      }
      throw error
    } catch {
      lastGemmaFailureReason = (error as? LocalizedError)?.errorDescription
        ?? "Analysis failed"
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
