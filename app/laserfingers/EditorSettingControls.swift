import SwiftUI

private enum EditorSettingRowLayout {
    static let titleWidth: CGFloat = 140
}

struct EditorSettingRow<Content: View>: View {
    let title: String
    private let alignment: VerticalAlignment
    private let content: () -> Content
    
    init(
        title: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.alignment = alignment
        self.content = content
    }
    
    var body: some View {
        HStack(alignment: alignment, spacing: 16) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: EditorSettingRowLayout.titleWidth, alignment: .leading)
            Spacer(minLength: 12)
            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

struct EditorTextFieldRow: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var lineLimit: Int? = nil
    var autocapitalization: TextInputAutocapitalization? = .sentences
    var disableAutocorrection = false
    var textAlignment: TextAlignment = .trailing
    
    var body: some View {
        EditorSettingRow(title: title, alignment: axis == .vertical ? .top : .center) {
            TextField(placeholder, text: $text, axis: axis)
                .editorLineLimit(lineLimit)
                .multilineTextAlignment(textAlignment)
                .textInputAutocapitalization(autocapitalization)
                .disableAutocorrection(disableAutocorrection)
                .frame(
                    maxWidth: axis == .vertical ? .infinity : 220,
                    alignment: axis == .vertical ? .leading : .trailing
                )
        }
    }
}

struct EditorNumberFieldRow: View {
    let title: String
    let placeholder: String
    @Binding var value: Double
    var format: FloatingPointFormatStyle<Double>
    
    init(
        title: String,
        placeholder: String = "",
        value: Binding<Double>,
        format: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(2))
    ) {
        self.title = title
        self.placeholder = placeholder
        self._value = value
        self.format = format
    }
    
    var body: some View {
        EditorSettingRow(title: title) {
            TextField(placeholder, value: $value, format: format)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 160)
        }
    }
}

struct EditorToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        EditorSettingRow(title: title) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

struct EditorChoiceRow<Selection: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: Selection
    private let content: () -> Content
    
    init(
        title: String,
        selection: Binding<Selection>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self._selection = selection
        self.content = content
    }
    
    var body: some View {
        EditorSettingRow(title: title) {
            Picker("", selection: $selection) {
                content()
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
}

struct EditorColorPickerRow: View {
    let title: String
    @Binding var hexValue: String
    
    var body: some View {
        EditorSettingRow(title: title) {
            HStack(spacing: 12) {
                ColorPicker("", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
                Text(hexValue.uppercased())
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 54)
            }
        }
    }
    
    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hexString: hexValue) },
            set: { newValue in
                if let hex = newValue.hexString {
                    hexValue = hex
                }
            }
        )
    }
}

struct EditorNullableNumberRow: View {
    let title: String
    @Binding var value: Double?
    var format: FloatingPointFormatStyle<Double>
    private let defaultValue: Double
    
    init(
        title: String,
        value: Binding<Double?>,
        defaultValue: Double,
        format: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(2))
    ) {
        self.title = title
        self._value = value
        self.defaultValue = defaultValue
        self.format = format
    }
    
    var body: some View {
        EditorNullableValueRow(title: title, value: $value, defaultValue: defaultValue) { binding in
            TextField("", value: binding, format: format)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 140)
        }
    }
}

private struct EditorNullableValueRow<Value: Equatable, Field: View>: View {
    let title: String
    @Binding private var value: Value?
    @State private var cachedValue: Value
    private let fieldBuilder: (Binding<Value>) -> Field
    
    init(
        title: String,
        value: Binding<Value?>,
        defaultValue: Value,
        @ViewBuilder field: @escaping (Binding<Value>) -> Field
    ) {
        self.title = title
        self._value = value
        self._cachedValue = State(initialValue: value.wrappedValue ?? defaultValue)
        self.fieldBuilder = field
    }
    
    var body: some View {
        EditorSettingRow(title: title) {
            HStack(spacing: 12) {
                if value != nil {
                    fieldBuilder(
                        Binding(
                            get: { value ?? cachedValue },
                            set: { newValue in
                                cachedValue = newValue
                                value = newValue
                            }
                        )
                    )
                }
                Toggle("", isOn: toggleBinding)
                    .labelsHidden()
            }
        }
        .onChange(of: value) { newValue in
            if let newValue {
                cachedValue = newValue
            }
        }
    }
    
    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { value != nil },
            set: { isOn in
                if isOn {
                    value = value ?? cachedValue
                } else {
                    cachedValue = value ?? cachedValue
                    value = nil
                }
            }
        )
    }
}

private struct EditorLineLimitModifier: ViewModifier {
    let lineLimit: Int?
    
    func body(content: Content) -> some View {
        if let lineLimit {
            content.lineLimit(lineLimit, reservesSpace: true)
        } else {
            content
        }
    }
}

private extension View {
    func editorLineLimit(_ lineLimit: Int?) -> some View {
        modifier(EditorLineLimitModifier(lineLimit: lineLimit))
    }
}

extension Color {
    init(hexString: String) {
        #if canImport(UIKit)
        self = Color(UIColor(hexString: hexString) ?? UIColor.white)
        #elseif canImport(AppKit)
        self = Color(NSColor(hexString: hexString) ?? NSColor.white)
        #else
        self = .white
        #endif
    }
    
    var hexString: String? {
        #if canImport(UIKit)
        return UIColor(self).hexString
        #elseif canImport(AppKit)
        return NSColor(self).hexString
        #else
        return nil
        #endif
    }
}

#if canImport(UIKit)
import UIKit
private extension UIColor {
    convenience init?(hexString: String) {
        guard let components = Self.rgbComponents(from: hexString) else { return nil }
        self.init(red: components.r, green: components.g, blue: components.b, alpha: 1)
    }
    
    var hexString: String? {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return UIColor.formatHex(r: r, g: g, b: b)
    }
    
    static func rgbComponents(from hexString: String) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        var cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        if cleaned.count == 3 {
            cleaned = cleaned.reduce(into: "") { partial, char in
                partial.append(String(repeating: char, count: 2))
            }
        }
        guard cleaned.count == 6, let value = UInt(cleaned, radix: 16) else {
            return nil
        }
        let r = CGFloat((value & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((value & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(value & 0x0000FF) / 255.0
        return (r, g, b)
    }
    
    static func formatHex(r: CGFloat, g: CGFloat, b: CGFloat) -> String {
        let red = Int(round(r * 255))
        let green = Int(round(g * 255))
        let blue = Int(round(b * 255))
        return String(format: "%02X%02X%02X", red, green, blue)
    }
}
#elseif canImport(AppKit)
import AppKit
private extension NSColor {
    convenience init?(hexString: String) {
        guard let components = Self.rgbComponents(from: hexString) else { return nil }
        self.init(srgbRed: components.r, green: components.g, blue: components.b, alpha: 1)
    }
    
    var hexString: String? {
        guard let color = usingColorSpace(.sRGB) else { return nil }
        return NSColor.formatHex(r: color.redComponent, g: color.greenComponent, b: color.blueComponent)
    }
    
    static func rgbComponents(from hexString: String) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        var cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        if cleaned.count == 3 {
            cleaned = cleaned.reduce(into: "") { partial, char in
                partial.append(String(repeating: char, count: 2))
            }
        }
        guard cleaned.count == 6, let value = UInt(cleaned, radix: 16) else {
            return nil
        }
        let r = CGFloat((value & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((value & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(value & 0x0000FF) / 255.0
        return (r, g, b)
    }
    
    static func formatHex(r: CGFloat, g: CGFloat, b: CGFloat) -> String {
        let red = Int(round(r * 255))
        let green = Int(round(g * 255))
        let blue = Int(round(b * 255))
        return String(format: "%02X%02X%02X", red, green, blue)
    }
}
#endif
