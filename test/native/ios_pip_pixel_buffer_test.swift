import CoreVideo
import Foundation

// Run with:
// swiftc packages/media_kit_video_patched/ios/Classes/plugin/PipPixelBuffer.swift \
//   test/native/ios_pip_pixel_buffer_test.swift -o /tmp/ios-pip-pixels && /tmp/ios-pip-pixels
@main
struct PipPixelBufferTests {
  static func source(width: Int = 6, height: Int = 4, value: UInt8) -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    precondition(CVPixelBufferCreate(kCFAllocatorDefault, width, height,
      kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess)
    let result = buffer!
    CVPixelBufferLockBaseAddress(result, [])
    let base = CVPixelBufferGetBaseAddress(result)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(result)
    for y in 0..<height {
      for x in 0..<width {
        for component in 0..<3 { base[y * stride + x * 4 + component] = value }
        base[y * stride + x * 4 + 3] = 0 // mpv bgr0 is not premultiplied alpha.
      }
    }
    CVPixelBufferUnlockBaseAddress(result, [])
    return result
  }

  static func assertPixels(_ buffer: CVPixelBuffer, luma: UInt8) {
    precondition(CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    precondition(CVPixelBufferGetIOSurface(buffer) != nil)
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    for plane in 0..<2 {
      let base = CVPixelBufferGetBaseAddressOfPlane(buffer, plane)!.assumingMemoryBound(to: UInt8.self)
      let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane)
      let width = CVPixelBufferGetWidth(buffer)
      let height = CVPixelBufferGetHeightOfPlane(buffer, plane)
      for y in 0..<height {
        for x in 0..<width {
          let expected = plane == 0 ? luma : 128
          precondition(abs(Int(base[y * stride + x]) - Int(expected)) <= 1)
        }
      }
    }
  }

  static func main() {
    let black = source(value: 0)
    let white = source(value: 255)
    let copiedBlack = PipPixelBuffer.copyForDisplay(black)!
    assertPixels(copiedBlack, luma: 16)
    assertPixels(PipPixelBuffer.copyForDisplay(white)!, luma: 235)
    // The source's next rendered frame cannot corrupt a queued PiP frame.
    CVPixelBufferLockBaseAddress(black, [])
    memset(CVPixelBufferGetBaseAddress(black)!, 255,
      CVPixelBufferGetBytesPerRow(black) * CVPixelBufferGetHeight(black))
    CVPixelBufferUnlockBaseAddress(black, [])
    assertPixels(copiedBlack, luma: 16)
    precondition(PipPixelBuffer.copyForDisplay(source(width: 5, value: 0)) == nil)
    print("PiP pixel tests passed: black, white, padded strides, independent ownership, odd dimensions")
  }
}
