import SpriteKit
import CoreGraphics

extension SKColor {
    static func fromHex(_ hex: String, alpha: CGFloat = 1.0) -> SKColor {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        if cleaned.count == 3 {
            cleaned = cleaned.reduce(into: "") { partial, char in
                partial.append(String(repeating: char, count: 2))
            }
        }
        guard cleaned.count == 6, let value = UInt(cleaned, radix: 16) else {
            return SKColor(red: 1, green: 1, blue: 1, alpha: alpha)
        }
        let red = CGFloat((value & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((value & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(value & 0x0000FF) / 255.0
        return SKColor(red: red, green: green, blue: blue, alpha: alpha)
    }
    
    func brightened(by amount: CGFloat) -> SKColor {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return self }
        let factor = 1 + amount
        return SKColor(red: min(r * factor, 1), green: min(g * factor, 1), blue: min(b * factor, 1), alpha: a)
    }
}
