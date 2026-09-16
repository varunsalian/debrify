import Accelerate
import CoreVideo

/// AVKit's cross-process video surface uses an IOSurface-backed NV12 frame.
/// Conversion also gives AVKit independent ownership of mpv's recycled buffers.
enum PipPixelBuffer {
  static func copyForDisplay(_ source: CVPixelBuffer) -> CVPixelBuffer? {
    let width = CVPixelBufferGetWidth(source)
    let height = CVPixelBufferGetHeight(source)
    guard width > 0, height > 0, width % 2 == 0, height % 2 == 0,
          CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_32BGRA else { return nil }
    var destination: CVPixelBuffer?
    guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      [kCVPixelBufferIOSurfacePropertiesKey: [:],
       kCVPixelBufferMetalCompatibilityKey: true] as CFDictionary,
      &destination) == kCVReturnSuccess, let destination = destination else { return nil }

    guard CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess else { return nil }
    defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
    guard CVPixelBufferLockBaseAddress(destination, []) == kCVReturnSuccess else { return nil }
    defer { CVPixelBufferUnlockBaseAddress(destination, []) }
    guard let src = CVPixelBufferGetBaseAddress(source),
          let y = CVPixelBufferGetBaseAddressOfPlane(destination, 0),
          let uv = CVPixelBufferGetBaseAddressOfPlane(destination, 1) else { return nil }
    var input = vImage_Buffer(data: src, height: vImagePixelCount(height),
      width: vImagePixelCount(width), rowBytes: CVPixelBufferGetBytesPerRow(source))
    var luma = vImage_Buffer(data: y, height: vImagePixelCount(height),
      width: vImagePixelCount(width), rowBytes: CVPixelBufferGetBytesPerRowOfPlane(destination, 0))
    var chroma = vImage_Buffer(data: uv, height: vImagePixelCount(height / 2),
      width: vImagePixelCount(width / 2), rowBytes: CVPixelBufferGetBytesPerRowOfPlane(destination, 1))
    var range = vImage_YpCbCrPixelRange(Yp_bias: 16, CbCr_bias: 128,
      YpRangeMax: 235, CbCrRangeMax: 240, YpMax: 235, YpMin: 16, CbCrMax: 240, CbCrMin: 16)
    var conversion = vImage_ARGBToYpCbCr()
    guard vImageConvert_ARGBToYpCbCr_GenerateConversion(
      kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2, &range, &conversion,
      kvImageARGB8888, kvImage420Yp8_CbCr8, vImage_Flags(kvImageNoFlags)) == kvImageNoError else { return nil }
    let map: [UInt8] = [3, 2, 1, 0] // BGRA -> ARGB; alpha is discarded.
    guard vImageConvert_ARGB8888To420Yp8_CbCr8(&input, &luma, &chroma,
      &conversion, map, vImage_Flags(kvImageNoFlags)) == kvImageNoError else { return nil }
    CVBufferSetAttachment(destination, kCVImageBufferYCbCrMatrixKey,
      kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
    CVBufferSetAttachment(destination, kCVImageBufferColorPrimariesKey,
      kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
    CVBufferSetAttachment(destination, kCVImageBufferTransferFunctionKey,
      kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
    return destination
  }
}
