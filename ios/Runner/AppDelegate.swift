import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var ppgChannel: PpgNativeChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "PpgNativeChannel") {
      ppgChannel = PpgNativeChannel(messenger: registrar.messenger())
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

// MARK: - Method channel

/// Method channel `com.samionyx.ppg_recorder/native`:
///  - `decodeVideoSignal {path, roiSize}` → per-frame ROI RGB means (decoded on a
///    background queue; progress reported via `onDecodeProgress`).
///  - `getFreeDiskSpace {path}` → available bytes on that volume.
final class PpgNativeChannel {
  private let channel: FlutterMethodChannel
  private let queue = DispatchQueue(
    label: "com.samionyx.ppg_recorder.decode", qos: .userInitiated)

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.samionyx.ppg_recorder/native", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "decodeVideoSignal":
      guard let path = args?["path"] as? String, !path.isEmpty else {
        result(FlutterError(
          code: "INVALID_ARGUMENT", message: "A video path is required.", details: nil))
        return
      }
      let roiSize = (args?["roiSize"] as? Int) ?? 64
      let channel = self.channel
      queue.async {
        do {
          let decoded = try VideoSignalDecoder(roiSize: roiSize).decode(path: path) { progress in
            DispatchQueue.main.async {
              channel.invokeMethod("onDecodeProgress", arguments: progress)
            }
          }
          DispatchQueue.main.async { result(decoded.toMap()) }
        } catch let error as VideoDecodeError {
          DispatchQueue.main.async {
            result(FlutterError(code: error.code, message: error.message, details: nil))
          }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(
              code: "DECODE_FAILED", message: error.localizedDescription, details: nil))
          }
        }
      }

    case "getFreeDiskSpace":
      let path = (args?["path"] as? String) ?? NSHomeDirectory()
      do {
        let values = try URL(fileURLWithPath: path).resourceValues(
          forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let bytes = values.volumeAvailableCapacityForImportantUsage {
          result(NSNumber(value: bytes))
        } else {
          result(nil)
        }
      } catch {
        result(FlutterError(
          code: "STAT_FAILED", message: error.localizedDescription, details: nil))
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

// MARK: - Video decoding

/// Failure with a stable error code forwarded to Dart.
struct VideoDecodeError: Error {
  let code: String
  let message: String
}

/// Per-frame ROI channel means of a decoded video plus decode details.
struct DecodedSignal {
  let timestampsUs: [Int64]
  let red: [Double]
  let green: [Double]
  let blue: [Double]
  let width: Int
  let height: Int
  let rotationDegrees: Int
  let durationUs: Int64

  /// Method-channel representation (typed data maps to Int64List / Float64List).
  func toMap() -> [String: Any] {
    return [
      "timestampsUs": FlutterStandardTypedData(
        int64: timestampsUs.withUnsafeBufferPointer { Data(buffer: $0) }),
      "red": FlutterStandardTypedData(float64: red.withUnsafeBufferPointer { Data(buffer: $0) }),
      "green": FlutterStandardTypedData(
        float64: green.withUnsafeBufferPointer { Data(buffer: $0) }),
      "blue": FlutterStandardTypedData(float64: blue.withUnsafeBufferPointer { Data(buffer: $0) }),
      "width": width,
      "height": height,
      "rotationDegrees": rotationDegrees,
      "durationUs": NSNumber(value: durationUs),
      "colorConversion":
        "AVFoundation YUV to BGRA conversion using the track's colour attachments",
      "decoderName": "AVAssetReader",
    ]
  }
}

/// Decodes every frame with AVAssetReader (BGRA output) and averages R/G/B over
/// a centred `roiSize` x `roiSize` square — the same ROI the Sphygma app uses.
/// Timestamps are the track's presentation times.
final class VideoSignalDecoder {
  private let roiSize: Int
  private static let progressEveryFrames = 10

  init(roiSize: Int) {
    self.roiSize = max(1, roiSize)
  }

  func decode(path: String, onProgress: @escaping (Double) -> Void) throws -> DecodedSignal {
    guard FileManager.default.fileExists(atPath: path) else {
      throw VideoDecodeError(code: "FILE_NOT_FOUND", message: "Video file is missing.")
    }
    let asset = AVURLAsset(
      url: URL(fileURLWithPath: path),
      options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
    guard let track = asset.tracks(withMediaType: .video).first else {
      throw VideoDecodeError(code: "NO_VIDEO_TRACK", message: "The file contains no video track.")
    }

    let reader: AVAssetReader
    do {
      reader = try AVAssetReader(asset: asset)
    } catch {
      throw VideoDecodeError(code: "IO_ERROR", message: error.localizedDescription)
    }
    let output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else {
      throw VideoDecodeError(code: "DECODER_ERROR", message: "Cannot read the video track.")
    }
    reader.add(output)
    guard reader.startReading() else {
      throw VideoDecodeError(
        code: "DECODER_ERROR",
        message: reader.error?.localizedDescription ?? "Could not start decoding.")
    }

    let durationSeconds = CMTimeGetSeconds(asset.duration)
    var timestamps: [Int64] = []
    var reds: [Double] = []
    var greens: [Double] = []
    var blues: [Double] = []
    timestamps.reserveCapacity(1024)
    reds.reserveCapacity(1024)
    greens.reserveCapacity(1024)
    blues.reserveCapacity(1024)
    var width = 0
    var height = 0

    while let sample = output.copyNextSampleBuffer() {
      guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
      let pts = CMSampleBufferGetPresentationTimeStamp(sample)
      guard pts.isValid, pts.isNumeric else { continue }
      let seconds = CMTimeGetSeconds(pts)
      let mean = try sampleRoi(pixelBuffer)
      timestamps.append(Int64((seconds * 1_000_000).rounded()))
      reds.append(mean.red)
      greens.append(mean.green)
      blues.append(mean.blue)
      width = mean.width
      height = mean.height
      if durationSeconds > 0, timestamps.count % Self.progressEveryFrames == 0 {
        onProgress(min(1, max(0, seconds / durationSeconds)))
      }
    }

    if reader.status == .failed {
      throw VideoDecodeError(
        code: "DECODER_ERROR",
        message: reader.error?.localizedDescription ?? "Decoding failed.")
    }
    if timestamps.isEmpty {
      throw VideoDecodeError(code: "NO_FRAMES", message: "No frames could be decoded.")
    }
    onProgress(1)

    let transform = track.preferredTransform
    var rotation = Int((atan2(Double(transform.b), Double(transform.a)) * 180 / .pi).rounded())
    rotation = ((rotation % 360) + 360) % 360

    return DecodedSignal(
      timestampsUs: timestamps,
      red: reds,
      green: greens,
      blue: blues,
      width: width,
      height: height,
      rotationDegrees: rotation,
      durationUs: durationSeconds.isFinite ? Int64((durationSeconds * 1_000_000).rounded()) : 0)
  }

  private func sampleRoi(_ pixelBuffer: CVPixelBuffer) throws -> (
    red: Double, green: Double, blue: Double, width: Int, height: Int
  ) {
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA,
      let base = CVPixelBufferGetBaseAddress(pixelBuffer)
    else {
      throw VideoDecodeError(code: "DECODER_ERROR", message: "Unexpected pixel format.")
    }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let pixels = base.assumingMemoryBound(to: UInt8.self)

    let half = roiSize / 2
    let x0 = max(0, width / 2 - half)
    let x1 = min(width, width / 2 + half)
    let y0 = max(0, height / 2 - half)
    let y1 = min(height, height / 2 + half)
    guard x1 > x0, y1 > y0 else {
      throw VideoDecodeError(code: "EMPTY_ROI", message: "The frame is too small.")
    }

    var red = 0.0
    var green = 0.0
    var blue = 0.0
    for y in y0..<y1 {
      let row = pixels + y * bytesPerRow
      for x in x0..<x1 {
        let pixel = row + x * 4
        blue += Double(pixel[0])
        green += Double(pixel[1])
        red += Double(pixel[2])
      }
    }
    let count = Double((x1 - x0) * (y1 - y0))
    return (red / count, green / count, blue / count, width, height)
  }
}
