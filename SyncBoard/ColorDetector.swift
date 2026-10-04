//
//  ColorDetector.swift
//  SyncBoard
//

import AppKit
import SwiftUI

struct DetectedColor: Equatable, Hashable {
    let rawString: String
    let color: Color
    let nsColor: NSColor

    var hexString: String {
        let r = Int(round(nsColor.redComponent * 255))
        let g = Int(round(nsColor.greenComponent * 255))
        let b = Int(round(nsColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    var rgbString: String {
        let r = Int(round(nsColor.redComponent * 255))
        let g = Int(round(nsColor.greenComponent * 255))
        let b = Int(round(nsColor.blueComponent * 255))
        if nsColor.alphaComponent < 0.999 {
            return String(format: "rgba(%d, %d, %d, %.2f)", r, g, b, nsColor.alphaComponent)
        }
        return String(format: "rgb(%d, %d, %d)", r, g, b)
    }

    var hslString: String {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let l = b * (1 - s / 2)
        let hslSat = (l == 0 || l == 1) ? 0 : (b - l) / min(l, 1 - l)
        return String(format: "hsl(%.0f, %.0f%%, %.0f%%)", h * 360, hslSat * 100, l * 100)
    }

    var swiftUIString: String {
        String(
            format: "Color(red: %.2f, green: %.2f, blue: %.2f)",
            nsColor.redComponent,
            nsColor.greenComponent,
            nsColor.blueComponent
        )
    }

    var nsColorCodeString: String {
        String(
            format: "NSColor(red: %.2f, green: %.2f, blue: %.2f, alpha: %.2f)",
            nsColor.redComponent,
            nsColor.greenComponent,
            nsColor.blueComponent,
            nsColor.alphaComponent
        )
    }
}

enum ColorDetector {
    static func detect(from text: String) -> DetectedColor? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 40 else { return nil }

        // HEX formats: #RGB, #RGBA, #RRGGBB, #RRGGBBAA, 0xRRGGBB
        if let hexColor = parseHex(trimmed) {
            return DetectedColor(rawString: trimmed, color: Color(nsColor: hexColor), nsColor: hexColor)
        }

        // RGB / RGBA formats: rgb(255, 100, 50), rgba(255, 100, 50, 0.8)
        if let rgbColor = parseRGB(trimmed) {
            return DetectedColor(rawString: trimmed, color: Color(nsColor: rgbColor), nsColor: rgbColor)
        }

        // HSL / HSLA formats: hsl(200, 80%, 50%), hsla(200, 80%, 50%, 0.8)
        if let hslColor = parseHSL(trimmed) {
            return DetectedColor(rawString: trimmed, color: Color(nsColor: hslColor), nsColor: hslColor)
        }

        return nil
    }

    private static func parseHex(_ string: String) -> NSColor? {
        var clean = string.replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
        if clean.hasPrefix("#") {
            clean.removeFirst()
        }
        guard clean.range(of: "^[0-9a-fA-F]+$", options: .regularExpression) != nil else { return nil }

        var rgbValue: UInt64 = 0
        guard Scanner(string: clean).scanHexInt64(&rgbValue) else { return nil }

        switch clean.count {
        case 3: // RGB (12-bit)
            let r = CGFloat((rgbValue >> 8) & 0xF) / 15.0
            let g = CGFloat((rgbValue >> 4) & 0xF) / 15.0
            let b = CGFloat(rgbValue & 0xF) / 15.0
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
        case 4: // RGBA (16-bit)
            let r = CGFloat((rgbValue >> 12) & 0xF) / 15.0
            let g = CGFloat((rgbValue >> 8) & 0xF) / 15.0
            let b = CGFloat((rgbValue >> 4) & 0xF) / 15.0
            let a = CGFloat(rgbValue & 0xF) / 15.0
            return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        case 6: // RRGGBB (24-bit)
            let r = CGFloat((rgbValue >> 16) & 0xFF) / 255.0
            let g = CGFloat((rgbValue >> 8) & 0xFF) / 255.0
            let b = CGFloat(rgbValue & 0xFF) / 255.0
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
        case 8: // RRGGBBAA (32-bit)
            let r = CGFloat((rgbValue >> 24) & 0xFF) / 255.0
            let g = CGFloat((rgbValue >> 16) & 0xFF) / 255.0
            let b = CGFloat((rgbValue >> 8) & 0xFF) / 255.0
            let a = CGFloat(rgbValue & 0xFF) / 255.0
            return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        default:
            return nil
        }
    }

    private static func parseRGB(_ string: String) -> NSColor? {
        let pattern = #"^rgba?\s*\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(?:,\s*([0-9.]+)\s*)?\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) else {
            return nil
        }

        func extract(at index: Int) -> String? {
            guard index < match.numberOfRanges, let r = Range(match.range(at: index), in: string) else { return nil }
            return String(string[r])
        }

        guard let rStr = extract(at: 1), let r = Double(rStr), (0...255).contains(r),
              let gStr = extract(at: 2), let g = Double(gStr), (0...255).contains(g),
              let bStr = extract(at: 3), let b = Double(bStr), (0...255).contains(b) else {
            return nil
        }

        let a = extract(at: 4).flatMap { Double($0) } ?? 1.0
        return NSColor(srgbRed: CGFloat(r / 255.0), green: CGFloat(g / 255.0), blue: CGFloat(b / 255.0), alpha: CGFloat(a))
    }

    private static func parseHSL(_ string: String) -> NSColor? {
        let pattern = #"^hsla?\s*\(\s*(\d{1,3})\s*,\s*(\d{1,3})%\s*,\s*(\d{1,3})%\s*(?:,\s*([0-9.]+)\s*)?\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) else {
            return nil
        }

        func extract(at index: Int) -> String? {
            guard index < match.numberOfRanges, let r = Range(match.range(at: index), in: string) else { return nil }
            return String(string[r])
        }

        guard let hStr = extract(at: 1), let h = Double(hStr), (0...360).contains(h),
              let sStr = extract(at: 2), let s = Double(sStr), (0...100).contains(s),
              let lStr = extract(at: 3), let l = Double(lStr), (0...100).contains(l) else {
            return nil
        }

        let a = extract(at: 4).flatMap { Double($0) } ?? 1.0
        let hue = CGFloat(h / 360.0)
        let saturation = CGFloat(s / 100.0)
        let lightness = CGFloat(l / 100.0)

        // Convert HSL to HSB for NSColor
        let brightness = lightness + saturation * min(lightness, 1 - lightness)
        let hsbSat = brightness == 0 ? 0 : 2 * (1 - lightness / brightness)

        return NSColor(calibratedHue: hue, saturation: hsbSat, brightness: brightness, alpha: CGFloat(a))
    }
}
