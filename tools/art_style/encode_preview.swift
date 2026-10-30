// macOS: swift tools/art_style/encode_preview.swift INPUT_DIRECTORY OUTPUT.mp4
// Encodes the actual Godot frame captures without interpolation or retiming.
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: encode_preview.swift INPUT_DIRECTORY OUTPUT.mp4")
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let frames = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    .filter { $0.lastPathComponent.hasPrefix("frame_") && $0.pathExtension == "png" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
guard let first = frames.first,
      let source = CGImageSourceCreateWithURL(first as CFURL, nil),
      let firstImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("No readable Godot frames")
}
let width = firstImage.width
let height = firstImage.height
if FileManager.default.fileExists(atPath: output.path) {
    try FileManager.default.removeItem(at: output)
}
let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000,
                                     AVVideoExpectedSourceFrameRateKey: 60]
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
    kCVPixelBufferCGImageCompatibilityKey as String: true,
    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
])
writer.add(input)
guard writer.startWriting() else { fatalError("Cannot start writer: \(String(describing: writer.error))") }
writer.startSession(atSourceTime: .zero)
for (index, frame) in frames.enumerated() {
    autoreleasepool {
        while !input.isReadyForMoreMediaData {
            guard writer.status == .writing else { fatalError("Encoder failed: \(String(describing: writer.error))") }
            Thread.sleep(forTimeInterval: 0.002)
        }
        guard let source = CGImageSourceCreateWithURL(frame as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width == width && image.height == height else { fatalError("Invalid frame \(frame.path)") }
        var buffer: CVPixelBuffer?
        guard let pool = adaptor.pixelBufferPool,
              CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
              let buffer = buffer else { fatalError("Pixel buffer allocation failed") }
        CVPixelBufferLockBaseAddress(buffer, [])
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        else { fatalError("Bitmap context creation failed") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 60))
        else { fatalError("Frame append failed: \(String(describing: writer.error))") }
    }
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else { fatalError("Movie incomplete: \(String(describing: writer.error))") }
let asset = AVURLAsset(url: output)
guard let track = asset.tracks(withMediaType: .video).first,
      abs(track.nominalFrameRate - 60) < 0.1,
      abs(CMTimeGetSeconds(asset.duration) - Double(frames.count) / 60) < 0.05 else {
    fatalError("Encoded timing does not match Godot frames")
}
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
let decoded = try generator.copyCGImage(at: .zero, actualTime: nil)
let poster = output.deletingPathExtension().appendingPathExtension("png")
guard let destination = CGImageDestinationCreateWithURL(poster as CFURL, "public.png" as CFString, 1, nil)
else { fatalError("Cannot write decoded verification frame") }
CGImageDestinationAddImage(destination, decoded, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Poster write failed") }
print("CARTOON_VIPER_MOVIE_PASS frames=\(frames.count) size=\(width)x\(height) fps=60 path=\(output.path)")
