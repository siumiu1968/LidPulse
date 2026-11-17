import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let side = 1024
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
let c = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                  bytesPerRow: side * 4, space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
c.translateBy(x: 0, y: CGFloat(side))
c.scaleBy(x: 1, y: -1)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
func round(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func fill(_ path: CGPath, _ ink: CGColor) {
    c.addPath(path); c.setFillColor(ink); c.fillPath()
}
func stroke(_ path: CGPath, _ ink: CGColor, _ width: CGFloat) {
    c.addPath(path); c.setStrokeColor(ink); c.setLineWidth(width); c.strokePath()
}
func linear(_ path: CGPath, _ shades: [CGColor], from: CGPoint, to: CGPoint) {
    c.saveGState(); c.addPath(path); c.clip()
    let gradient = CGGradient(colorsSpace: rgb, colors: shades as CFArray, locations: nil)!
    c.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
}
func halo(_ shades: [CGColor], at center: CGPoint, radius: CGFloat) {
    let gradient = CGGradient(colorsSpace: rgb, colors: shades as CFArray, locations: nil)!
    c.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                         endCenter: center, endRadius: radius, options: [])
}

let tile = round(CGRect(x: 58, y: 52, width: 908, height: 908), 208)
c.saveGState()
c.setShadow(offset: CGSize(width: 0, height: -14), blur: 27, color: color(0x000000, 0.32))
fill(tile, color(0x101d2b))
c.restoreGState()
linear(tile, [color(0x2a465b), color(0x132437), color(0x0a121e)],
       from: CGPoint(x: 200, y: 60), to: CGPoint(x: 840, y: 970))
c.saveGState()
c.addPath(tile); c.clip()
halo([color(0x93dadc, 0.32), color(0x528891, 0.11), color(0x37727d, 0)],
     at: CGPoint(x: 475, y: 284), radius: 590)
c.restoreGState()
stroke(round(CGRect(x: 62, y: 56, width: 900, height: 900), 204), color(0xb8d3e4, 0.26), 4)

let lid = round(CGRect(x: 216, y: 302, width: 592, height: 386), 50)
c.saveGState()
c.setShadow(offset: CGSize(width: 0, height: -22), blur: 39, color: color(0x03070c, 0.66))
fill(lid, color(0x0b1927))
c.restoreGState()
linear(lid, [color(0x345063), color(0x182c41), color(0x0c1828)],
       from: CGPoint(x: 300, y: 286), to: CGPoint(x: 655, y: 688))
stroke(lid, color(0xb1d7e8, 0.51), 6)
stroke(round(CGRect(x: 223, y: 309, width: 578, height: 372), 44), color(0xb6dce7, 0.09), 3)

let center = CGPoint(x: 512, y: 490)
c.saveGState()
c.addPath(lid); c.clip()
halo([color(0x48f7d3, 0.39), color(0x47d1cc, 0.19), color(0x319bb0, 0)],
     at: center, radius: 252)
c.restoreGState()

let pulse = CGMutablePath()
pulse.move(to: CGPoint(x: 325, y: 500))
pulse.addLine(to: CGPoint(x: 420, y: 500))
pulse.addQuadCurve(to: CGPoint(x: 440, y: 484), control: CGPoint(x: 434, y: 500))
pulse.addLine(to: CGPoint(x: 470, y: 429))
pulse.addQuadCurve(to: CGPoint(x: 489, y: 434), control: CGPoint(x: 480, y: 409))
pulse.addLine(to: CGPoint(x: 531, y: 554))
pulse.addQuadCurve(to: CGPoint(x: 552, y: 555), control: CGPoint(x: 540, y: 582))
pulse.addLine(to: CGPoint(x: 573, y: 515))
pulse.addQuadCurve(to: CGPoint(x: 596, y: 500), control: CGPoint(x: 582, y: 500))
pulse.addLine(to: CGPoint(x: 699, y: 500))
c.setLineCap(.round); c.setLineJoin(.round)
c.saveGState()
c.setShadow(offset: .zero, blur: 30, color: color(0x4bffd4, 0.9))
stroke(pulse, color(0xaaffeb), 24)
c.restoreGState()
stroke(pulse, color(0xe4fff7), 13)

let hinge = round(CGRect(x: 198, y: 708, width: 628, height: 27), 13.5)
linear(hinge, [color(0x6a8698), color(0x253d54)],
       from: CGPoint(x: 512, y: 707), to: CGPoint(x: 512, y: 737))
stroke(round(CGRect(x: 447, y: 708, width: 130, height: 4), 2), color(0xcbf2ea, 0.56), 1)

let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, UTType.png.identifier as CFString, 1, nil
)!
CGImageDestinationAddImage(destination, c.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))
