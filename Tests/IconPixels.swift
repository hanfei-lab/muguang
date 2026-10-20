import Foundation
import ImageIO
import CoreGraphics

let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { fatalError("Unreadable ICNS") }
var sizes: [Int: Int] = [:]
for index in 0..<CGImageSourceGetCount(source) {
    guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { fatalError("Undecodable representation") }
    let w = image.width, h = image.height
    precondition(w == h)
    sizes[w, default: 0] += 1
    var rgba = [UInt8](repeating: 0, count: w * h * 4)
    rgba.withUnsafeMutableBytes { bytes in
        let context = CGContext(data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    let alpha = stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
    precondition(alpha.min() == 0 && alpha.max() == 255, "Broken transparency at \(w)px")
    precondition(rgba[(h / 2 * w + w / 2) * 4 + 3] > 200, "Blank icon at \(w)px")
    let red = stride(from: 0, to: rgba.count, by: 4).map { rgba[$0] }
    precondition(Int(red.max()!) - Int(red.min()!) > 80, "Missing artwork at \(w)px")
}
precondition(sizes == [16: 1, 32: 2, 64: 1, 128: 1, 256: 2, 512: 2, 1024: 1], "Missing icon sizes: \(sizes)")
print("PASS: all 10 decoded icon representations contain visible artwork and valid transparency")
