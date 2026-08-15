import Flutter
import UIKit
import AVFoundation
import Speech
import AudioToolbox

public class SttRecordPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let audioEngine = AVAudioEngine()
  private var speechRecognizer: SFSpeechRecognizer?
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?

  private let recognitionRequestLock = NSLock()

  private let amplitudeLock = NSLock()
  private var lastAmplitude: Double = 0.0

  private var audioFileURL: URL?

  private let fileQueue = DispatchQueue(label: "vn.fighttechvn.stt_record.file")
  private var wavWriter: WavFileWriter?

  private var eventSink: FlutterEventSink?
  private var tapInstalled = false

  private var isRunning = false
  private var isInterrupted = false
  private var isPausedByUser = false
  private var partialResultsEnabled = true
  private var localeId = "vi-VN"

  private var resumeAttempt: Int = 0
  private var resumeWorkItem: DispatchWorkItem?

  private let desiredSampleRate: Double = 16_000
  private let desiredChannels: AVAudioChannelCount = 1

  private var fileFormat: AVAudioFormat?
  private var audioConverter: AVAudioConverter?
  private var audioConverterInputFormat: AVAudioFormat?

  private var accumulatedFinalTranscript = ""
  private var lastFinalSegment = ""
  private var lastPartialSegment = ""

  private let stateQueue = DispatchQueue(label: "vn.fighttechvn.stt_record.state")

  public override init() {
    super.init()

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioSessionInterruption(_:)),
      name: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance()
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let methodChannel = FlutterMethodChannel(
      name: "stt_record/methods",
      binaryMessenger: registrar.messenger()
    )
    let eventChannel = FlutterEventChannel(
      name: "stt_record/events",
      binaryMessenger: registrar.messenger()
    )

    let instance = SttRecordPlugin()
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    stateQueue.async {
      self.eventSink = events
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stateQueue.async {
      self.eventSink = nil
    }
    return nil
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "hasPermission":
      result(self.hasPermission())

    case "requestPermission":
      self.requestPermission(result: result)

    case "start":
      let args = (call.arguments as? [String: Any]) ?? [:]
      let localeId = (args["localeId"] as? String) ?? "vi-VN"
      let partialResults = (args["partialResults"] as? Bool) ?? true
      self.start(localeId: localeId, partialResults: partialResults, result: result)

    case "pause":
      self.pause(result: result)

    case "resume":
      self.resume(result: result)

    case "stop":
      self.stop(result: result)

    case "cancel":
      self.cancel(result: result)

    case "getAmplitude":
      result(self.getAmplitude())

    case "getLocales":
      self.getLocales(result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @objc private func handleAudioSessionInterruption(_ notification: Notification) {
    guard let info = notification.userInfo,
          let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
      return
    }

    switch type {
    case .began:
      self.stateQueue.async {
        self.cancelResumeRetry()
        self.isInterrupted = true
        self.setAmplitude(0.0)
        guard self.isRunning else { return }

        self.flushPartialTranscriptAsFinal()
        self.sendTranscript(text: self.accumulatedFinalTranscript, isFinal: true)
        self.sendState(state: "paused")

        if self.audioEngine.isRunning {
          self.audioEngine.stop()
        }

        self.audioEngine.reset()

        if self.tapInstalled {
          self.audioEngine.inputNode.removeTap(onBus: 0)
          self.tapInstalled = false
        }

        self.recognitionTask?.cancel()
        self.recognitionTask = nil

        let reqToEnd: SFSpeechAudioBufferRecognitionRequest?
        self.recognitionRequestLock.lock()
        reqToEnd = self.recognitionRequest
        self.recognitionRequest = nil
        self.recognitionRequestLock.unlock()
        reqToEnd?.endAudio()

        // Best-effort deactivate to fully release mic resources.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      }

    case .ended:
      self.stateQueue.async {
        // Only resume if the session is still intended to run.
        guard self.isRunning else {
          self.isInterrupted = false
          return
        }

        self.isInterrupted = false

        // Do not auto-resume if user paused manually.
        guard !self.isPausedByUser else { return }

        // Some devices need a short grace period before mic becomes available again.
        // Retry with backoff until resumed or the session is stopped.
        self.attemptResumeFromInterruption()
      }

    @unknown default:
      break
    }
  }
}

private extension SttRecordPlugin {
  func cancelResumeRetry() {
    self.resumeWorkItem?.cancel()
    self.resumeWorkItem = nil
    self.resumeAttempt = 0
  }

  func attemptResumeFromInterruption() {
    if !self.isRunning { return }
    if self.isInterrupted { return }
    if self.isPausedByUser { return }

    self.resumeWorkItem?.cancel()
    self.resumeWorkItem = nil

    if self.performResumeAttempt() {
      self.resumeAttempt = 0
      return
    }

    self.scheduleResumeRetry()
  }

  func scheduleResumeRetry() {
    if !self.isRunning { return }
    if self.isInterrupted { return }
    if self.isPausedByUser { return }

    self.resumeAttempt += 1
    let delaySeconds = min(10.0, Double(self.resumeAttempt))

    let work = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      self.stateQueue.async {
        self.attemptResumeFromInterruption()
      }
    }

    self.resumeWorkItem?.cancel()
    self.resumeWorkItem = work

    self.stateQueue.asyncAfter(deadline: .now() + delaySeconds, execute: work)
  }

  func performResumeAttempt() -> Bool {
    if !self.isRunning { return false }
    if self.isInterrupted { return false }
    if self.isPausedByUser { return false }
    do {
      try self.configureAudioSession()
    } catch {
      return false
    }

    if self.speechRecognizer == nil {
      self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: self.localeId))
    }

    if let recognizer = self.speechRecognizer, recognizer.isAvailable {
      try? self.startRecognitionTask(with: recognizer)
    }

    if !self.audioEngine.isRunning {
      self.audioEngine.reset()
    }

    // Re-install tap to handle route/format changes after interruption.
    if self.tapInstalled {
      self.audioEngine.inputNode.removeTap(onBus: 0)
      self.tapInstalled = false
    }

    self.audioConverter = nil
    self.audioConverterInputFormat = nil

    self.installTapIfNeeded()

    if !self.audioEngine.isRunning {
      self.audioEngine.prepare()
      do {
        try self.audioEngine.start()
      } catch {
        return false
      }
    }

    self.sendState(state: "resumed")
    self.cancelResumeRetry()
    return true
  }

  func clearTranscriptState() {
    self.accumulatedFinalTranscript = ""
    self.lastFinalSegment = ""
    self.lastPartialSegment = ""
  }

  func appendFinalSegment(_ segment: String) {
    let cleaned = segment.trimmingCharacters(in: .whitespacesAndNewlines)
    if cleaned.isEmpty { return }
    if cleaned == self.lastFinalSegment { return }
    if !self.accumulatedFinalTranscript.isEmpty {
      self.accumulatedFinalTranscript += " "
    }
    self.accumulatedFinalTranscript += cleaned
    self.lastFinalSegment = cleaned
    self.lastPartialSegment = ""
  }

  func buildFullTranscript(currentPartial: String?) -> String {
    let partial = (currentPartial ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if self.accumulatedFinalTranscript.isEmpty { return partial }
    if partial.isEmpty { return self.accumulatedFinalTranscript }
    if partial == self.lastFinalSegment { return self.accumulatedFinalTranscript }
    return self.accumulatedFinalTranscript + " " + partial
  }

  func flushPartialTranscriptAsFinal() {
    let partial = self.lastPartialSegment
    if partial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
    self.appendFinalSegment(partial)
  }

  func installTapIfNeeded() {
    if self.tapInstalled { return }

    let inputNode = self.audioEngine.inputNode
    let inputFormat = inputNode.outputFormat(forBus: 0)

    inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
      guard let self = self else { return }

      // Feed STT with the original input buffers.
      self.recognitionRequestLock.lock()
      self.recognitionRequest?.append(buffer)
      self.recognitionRequestLock.unlock()

      // Convert to a stable file/STT format to avoid write failures after route changes.
      guard let targetFormat = self.fileFormat,
            let converted = self.convert(buffer: buffer, to: targetFormat) else {
        return
      }

      self.updateAmplitude(fromPcm16: converted)

      let audioData = self.pcmData(from: converted)
      if audioData.isEmpty { return }

      self.fileQueue.async { [weak self] in
        guard let self = self else { return }
        self.wavWriter?.appendPcmData(audioData)
      }
    }

    self.tapInstalled = true
  }

  func isSameFormat(_ a: AVAudioFormat, _ b: AVAudioFormat) -> Bool {
    return a.sampleRate == b.sampleRate &&
      a.channelCount == b.channelCount &&
      a.commonFormat == b.commonFormat &&
      a.isInterleaved == b.isInterleaved
  }

  func convert(buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
    let inputFormat = buffer.format
    if self.isSameFormat(inputFormat, targetFormat) {
      return buffer
    }

    if self.audioConverter == nil || self.audioConverterInputFormat == nil || !self.isSameFormat(self.audioConverterInputFormat!, inputFormat) {
      self.audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
      self.audioConverterInputFormat = inputFormat
    }

    guard let converter = self.audioConverter else { return nil }

    let ratio = targetFormat.sampleRate / inputFormat.sampleRate
    let outCapacityDouble = Swift.max(1.0, Double(buffer.frameLength) * ratio + 1.0)
    let outCapacity = AVAudioFrameCount(outCapacityDouble)
    guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else { return nil }

    var error: NSError?
    var didProvideInput = false
    let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
      if didProvideInput {
        // Treat input as a continuous stream across calls.
        outStatus.pointee = .noDataNow
        return nil
      }
      didProvideInput = true
      outStatus.pointee = .haveData
      return buffer
    }

    if status == .error { return nil }
    if error != nil { return nil }
    if outBuffer.frameLength == 0 { return nil }
    return outBuffer
  }

  func hasPermission() -> Bool {
    let micGranted = AVAudioSession.sharedInstance().recordPermission == .granted
    let speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
    return micGranted && speechGranted
  }

  func requestPermission(result: @escaping FlutterResult) {
    let group = DispatchGroup()

    var micGranted = false
    var speechGranted = false

    group.enter()
    AVAudioSession.sharedInstance().requestRecordPermission { granted in
      micGranted = granted
      group.leave()
    }

    group.enter()
    SFSpeechRecognizer.requestAuthorization { status in
      speechGranted = (status == .authorized)
      group.leave()
    }

    group.notify(queue: .main) {
      result(micGranted && speechGranted)
    }
  }

  func getLocales(result: @escaping FlutterResult) {
    var locales = [[String: String]]()
    let supported = SFSpeechRecognizer.supportedLocales()

    var currentLocaleId = Locale.current.identifier
    if let preferred = Locale.preferredLanguages.first, !preferred.isEmpty {
      currentLocaleId = preferred
    }

    if let entry = self.buildLocaleEntry(forIdentifier: currentLocaleId) {
      locales.append(entry)
    }

    let currentId = locales.first?["localeId"]
    let others = supported
      .compactMap { self.buildLocaleEntry(forIdentifier: $0.identifier) }
      .filter { ($0["localeId"] ?? "") != (currentId ?? "") }
      .sorted { ($0["localeId"] ?? "") < ($1["localeId"] ?? "") }

    locales.append(contentsOf: others)

    var seen = Set<String>()
    let unique = locales.filter { entry in
      guard let id = entry["localeId"], !id.isEmpty else { return false }
      return seen.insert(id).inserted
    }

    DispatchQueue.main.async {
      result(unique)
    }
  }

  func buildLocaleEntry(forIdentifier identifier: String) -> [String: String]? {
    let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return nil }

    let localeId = self.normalizeLocaleId(trimmed)
    if localeId.isEmpty { return nil }

    let rawName = Locale.current.localizedString(forIdentifier: trimmed) ??
      Locale.current.localizedString(forIdentifier: localeId)
    let name = (rawName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? localeId

    return ["localeId": localeId, "name": name]
  }

  func normalizeLocaleId(_ identifier: String) -> String {
    let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "" }
    // Prefer BCP-47-ish tags to match Android/Flutter conventions.
    return trimmed.replacingOccurrences(of: "_", with: "-")
  }

  func start(localeId: String, partialResults: Bool, result: @escaping FlutterResult) {
    stateQueue.async {
      if self.isRunning {
        DispatchQueue.main.async {
          result(FlutterError(code: "already_running", message: "A session is already running", details: nil))
        }
        return
      }

      if !self.hasPermission() {
        DispatchQueue.main.async {
          result(FlutterError(code: "permission_denied", message: "Microphone and speech recognition permissions are required", details: nil))
        }
        return
      }

      self.localeId = localeId
      self.partialResultsEnabled = partialResults
      self.isInterrupted = false
      self.isPausedByUser = false
      self.cancelResumeRetry()
      self.clearTranscriptState()
      self.setAmplitude(0.0)

      do {
        try self.resetSession(shouldDeleteFile: false)
        try self.configureAudioSession()
        try self.startEngineAndRecognition()
        self.isRunning = true
        DispatchQueue.main.async { result(nil) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "start_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func pause(result: @escaping FlutterResult) {
    stateQueue.async {
      if !self.isRunning {
        DispatchQueue.main.async { result(nil) }
        return
      }

      let alreadyPaused = self.isInterrupted || self.isPausedByUser
      self.isPausedByUser = true
      self.cancelResumeRetry()
      self.setAmplitude(0.0)

      if alreadyPaused {
        DispatchQueue.main.async { result(nil) }
        return
      }

      self.flushPartialTranscriptAsFinal()
      self.sendTranscript(text: self.accumulatedFinalTranscript, isFinal: true)
      self.sendState(state: "paused")

      if self.audioEngine.isRunning {
        self.audioEngine.stop()
      }

      self.audioEngine.reset()

      if self.tapInstalled {
        self.audioEngine.inputNode.removeTap(onBus: 0)
        self.tapInstalled = false
      }

      self.recognitionTask?.cancel()
      self.recognitionTask = nil

      let reqToEnd: SFSpeechAudioBufferRecognitionRequest?
      self.recognitionRequestLock.lock()
      reqToEnd = self.recognitionRequest
      self.recognitionRequest = nil
      self.recognitionRequestLock.unlock()
      reqToEnd?.endAudio()

      // Best-effort deactivate to fully release mic resources.
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

      DispatchQueue.main.async { result(nil) }
    }
  }

  func resume(result: @escaping FlutterResult) {
    stateQueue.async {
      if !self.isRunning {
        self.isPausedByUser = false
        DispatchQueue.main.async { result(nil) }
        return
      }

      if !self.isPausedByUser && !self.isInterrupted {
        DispatchQueue.main.async { result(nil) }
        return
      }

      self.isPausedByUser = false

      // If still interrupted (e.g. in a call), resume will happen after interruption ends.
      if self.isInterrupted {
        DispatchQueue.main.async { result(nil) }
        return
      }

      self.attemptResumeFromInterruption()
      DispatchQueue.main.async { result(nil) }
    }
  }

  func stop(result: @escaping FlutterResult) {
    stateQueue.async {
      if !self.isRunning {
        let path = self.audioFileURL?.path ?? ""
        DispatchQueue.main.async {
          result(["audioPath": path])
        }
        return
      }

      self.isRunning = false
      self.isInterrupted = false
      self.isPausedByUser = false
      self.cancelResumeRetry()
      self.setAmplitude(0.0)

      self.flushPartialTranscriptAsFinal()
      self.sendTranscript(text: self.accumulatedFinalTranscript, isFinal: true)

      self.audioEngine.stop()
      if self.tapInstalled {
        self.audioEngine.inputNode.removeTap(onBus: 0)
        self.tapInstalled = false
      }

      let reqToEnd: SFSpeechAudioBufferRecognitionRequest?
      self.recognitionRequestLock.lock()
      reqToEnd = self.recognitionRequest
      self.recognitionRequest = nil
      self.recognitionRequestLock.unlock()
      reqToEnd?.endAudio()

      // Close the audio file to finalize the WAV container.
      self.fileQueue.sync { }
      self.wavWriter?.finalize()
      self.wavWriter = nil

      let path = self.audioFileURL?.path ?? ""

      do {
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      } catch {
        // Ignore deactivation errors.
      }

      DispatchQueue.main.async {
        result(["audioPath": path])
      }
    }
  }

  func cancel(result: @escaping FlutterResult) {
    stateQueue.async {
      do {
        try self.resetSession(shouldDeleteFile: true)
        DispatchQueue.main.async { result(nil) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "cancel_failed", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  func resetSession(shouldDeleteFile: Bool) throws {
    if self.audioEngine.isRunning {
      self.audioEngine.stop()
    }

    if self.tapInstalled {
      self.audioEngine.inputNode.removeTap(onBus: 0)
      self.tapInstalled = false
    }

    self.recognitionTask?.cancel()
    self.recognitionTask = nil

    let reqToEnd: SFSpeechAudioBufferRecognitionRequest?
    self.recognitionRequestLock.lock()
    reqToEnd = self.recognitionRequest
    self.recognitionRequest = nil
    self.recognitionRequestLock.unlock()
    reqToEnd?.endAudio()

    self.cancelResumeRetry()

    self.fileQueue.sync { }
    self.wavWriter?.finalize()
    self.wavWriter = nil

    if shouldDeleteFile, let url = self.audioFileURL {
      try? FileManager.default.removeItem(at: url)
    }
    self.audioFileURL = nil

    self.isRunning = false
    self.isInterrupted = false
    self.isPausedByUser = false

    self.setAmplitude(0.0)

    self.fileFormat = nil
    self.audioConverter = nil
    self.audioConverterInputFormat = nil

    self.clearTranscriptState()
  }

  func configureAudioSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetooth, .defaultToSpeaker])
    try? session.setPreferredSampleRate(self.desiredSampleRate)
    try? session.setPreferredInputNumberOfChannels(Int(self.desiredChannels))
    try session.setActive(true, options: .notifyOthersOnDeactivation)
  }

  func startEngineAndRecognition() throws {
    let inputNode = self.audioEngine.inputNode

    // Stable output format (WAV + STT) to survive route/format changes.
    let targetFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: self.desiredSampleRate,
      channels: self.desiredChannels,
      interleaved: false
    )
    guard let fileFormat = targetFormat else {
      throw NSError(domain: "stt_record", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create target audio format"]) 
    }
    self.fileFormat = fileFormat
    self.audioConverter = nil
    self.audioConverterInputFormat = nil

    // Prepare file URL in temp directory.
    let fileName = "stt_record_\(Int(Date().timeIntervalSince1970)).wav"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    self.audioFileURL = url

    // Prepare WAV writer (manual) to survive interruption edge-cases.
    try self.fileQueue.sync {
      self.wavWriter?.finalize()
      self.wavWriter = try WavFileWriter(
        url: url,
        sampleRate: UInt32(self.desiredSampleRate),
        channels: UInt16(self.desiredChannels),
        bitsPerSample: 16
      )
    }

    // Speech recognizer.
    self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: self.localeId))
    guard let speechRecognizer = self.speechRecognizer else {
      throw NSError(domain: "stt_record", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create SFSpeechRecognizer"]) 
    }

    if !speechRecognizer.isAvailable {
      throw NSError(domain: "stt_record", code: 2, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is not available"]) 
    }

    try self.startRecognitionTask(with: speechRecognizer)

    self.installTapIfNeeded()

    self.audioEngine.prepare()
    try self.audioEngine.start()
  }

  func startRecognitionTask(with speechRecognizer: SFSpeechRecognizer) throws {
    self.recognitionTask?.cancel()
    self.recognitionTask = nil

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = self.partialResultsEnabled

    let task = speechRecognizer.recognitionTask(with: request) { [weak self] recognitionResult, error in
      guard let self = self else { return }

      if let recognitionResult = recognitionResult {
        let segment = recognitionResult.bestTranscription.formattedString
        self.stateQueue.async {
          self.lastPartialSegment = segment

          if recognitionResult.isFinal {
            self.appendFinalSegment(segment)
            self.sendTranscript(text: self.accumulatedFinalTranscript, isFinal: true)

            // SFSpeech has practical session/time limits; restart to keep realtime running.
            guard self.isRunning, !self.isInterrupted, !self.isPausedByUser, let recognizer = self.speechRecognizer else { return }
            try? self.startRecognitionTask(with: recognizer)
          } else {
            let full = self.buildFullTranscript(currentPartial: segment)
            self.sendTranscript(text: full, isFinal: false)
          }
        }
      }

      if error != nil {
        // Best-effort auto-restart while keeping recording alive.
        self.stateQueue.async {
          guard self.isRunning, !self.isInterrupted, !self.isPausedByUser, let recognizer = self.speechRecognizer else { return }
          self.flushPartialTranscriptAsFinal()
          self.sendTranscript(text: self.accumulatedFinalTranscript, isFinal: true)
          try? self.startRecognitionTask(with: recognizer)
        }
      }
    }

    let oldReqToEnd: SFSpeechAudioBufferRecognitionRequest?
    self.recognitionRequestLock.lock()
    oldReqToEnd = self.recognitionRequest
    self.recognitionRequest = request
    self.recognitionRequestLock.unlock()
    oldReqToEnd?.endAudio()

    self.recognitionTask = task
  }

  func pcmData(from buffer: AVAudioPCMBuffer) -> Data {
    // Expecting PCM16 16kHz mono (but handle any interleaving).
    let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
    guard abl.count > 0 else { return Data() }
    guard let ptr = abl[0].mData else { return Data() }

    let available = Int(abl[0].mDataByteSize)
    if available <= 0 { return Data() }

    let bytesPerFrame = Int(buffer.format.streamDescription.pointee.mBytesPerFrame)
    let expected = Int(buffer.frameLength) * bytesPerFrame

    let byteCount: Int
    if expected > 0 {
      byteCount = min(available, expected)
    } else if bytesPerFrame > 0 {
      // Fallback: some conversions may not populate frameLength consistently.
      byteCount = available - (available % bytesPerFrame)
    } else {
      byteCount = available
    }

    if byteCount <= 0 { return Data() }

    return Data(bytes: ptr, count: byteCount)
  }

  func updateAmplitude(fromPcm16 buffer: AVAudioPCMBuffer) {
    guard buffer.format.commonFormat == .pcmFormatInt16 else { return }
    guard let channels = buffer.int16ChannelData else { return }
    let frames = Int(buffer.frameLength)
    if frames <= 0 { return }

    let samples = channels[0]
    var peak: Int32 = 0
    for i in 0..<frames {
      let v = Int32(samples[i])
      let absV = Swift.abs(v)
      if absV > peak { peak = absV }
    }

    let normalized = Double(peak) / 32768.0
    self.setAmplitude(normalized)
  }

  func setAmplitude(_ value: Double) {
    let clamped = min(1.0, max(0.0, value))
    self.amplitudeLock.lock()
    self.lastAmplitude = clamped
    self.amplitudeLock.unlock()
  }

  func getAmplitude() -> Double {
    self.amplitudeLock.lock()
    let v = self.lastAmplitude
    self.amplitudeLock.unlock()
    return v
  }


private final class WavFileWriter {
  private let url: URL
  private let sampleRate: UInt32
  private let channels: UInt16
  private let bitsPerSample: UInt16

  private var fileHandle: FileHandle?
  private var dataBytesWritten: UInt64 = 0
  private var finalized: Bool = false

  init(url: URL, sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16) throws {
    self.url = url
    self.sampleRate = sampleRate
    self.channels = channels
    self.bitsPerSample = bitsPerSample

    FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
    let fh = try FileHandle(forWritingTo: url)
    self.fileHandle = fh

    // Placeholder header.
    let header = Self.makeHeader(
      dataSize: 0,
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample
    )
    fh.seek(toFileOffset: 0)
    fh.write(header)
  }

  func appendPcmData(_ data: Data) {
    guard !finalized else { return }
    guard let fh = self.fileHandle else { return }
    if data.isEmpty { return }

    fh.write(data)
    self.dataBytesWritten += UInt64(data.count)
  }

  func finalize() {
    guard !finalized else { return }
    self.finalized = true

    guard let fh = self.fileHandle else { return }
    self.fileHandle = nil

    let dataSize = UInt32(min(self.dataBytesWritten, UInt64(UInt32.max)))
    let header = Self.makeHeader(
      dataSize: dataSize,
      sampleRate: self.sampleRate,
      channels: self.channels,
      bitsPerSample: self.bitsPerSample
    )

    fh.seek(toFileOffset: 0)
    fh.write(header)

    if #available(iOS 13.0, *) {
      try? fh.close()
    } else {
      fh.closeFile()
    }
  }

  private static func makeHeader(
    dataSize: UInt32,
    sampleRate: UInt32,
    channels: UInt16,
    bitsPerSample: UInt16
  ) -> Data {
    let blockAlign = UInt16(channels * (bitsPerSample / 8))
    let byteRate = sampleRate * UInt32(blockAlign)
    let chunkSize = UInt32(36) + dataSize

    var d = Data()
    d.appendAscii("RIFF")
    d.appendLE(chunkSize)
    d.appendAscii("WAVE")
    d.appendAscii("fmt ")
    d.appendLE(UInt32(16))
    d.appendLE(UInt16(1))
    d.appendLE(channels)
    d.appendLE(sampleRate)
    d.appendLE(byteRate)
    d.appendLE(blockAlign)
    d.appendLE(bitsPerSample)
    d.appendAscii("data")
    d.appendLE(dataSize)
    return d
  }
}

  func sendTranscript(text: String, isFinal: Bool) {
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if cleaned.isEmpty { return }
    guard let sink = self.eventSink else { return }
    DispatchQueue.main.async {
      sink(["event": "transcript", "text": cleaned, "isFinal": isFinal])
    }
  }

  func sendState(state: String) {
    guard let sink = self.eventSink else { return }
    DispatchQueue.main.async {
      sink(["event": "state", "state": state])
    }
  }
}

private extension Data {
  mutating func appendAscii(_ value: String) {
    if let bytes = value.data(using: .ascii) {
      self.append(bytes)
    }
  }

  mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
    var v = value.littleEndian
    Swift.withUnsafeBytes(of: &v) { raw in
      self.append(contentsOf: raw)
    }
  }
}
