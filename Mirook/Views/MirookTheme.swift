import AppKit
import CoreText
import SwiftUI

enum MirookFontRegistrar {
    nonisolated(unsafe) private static var didRegisterVazirmatn = false

    static func registerVazirmatnIfNeeded() {
        guard !didRegisterVazirmatn else {
            return
        }

        didRegisterVazirmatn = true
        ["Vazirmatn-Regular", "Vazirmatn-Bold"].forEach { fontName in
            guard let url = Bundle.main.url(forResource: fontName, withExtension: "ttf") else {
                return
            }

            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func vazirmatnRegular(size: CGFloat) -> NSFont {
        registerVazirmatnIfNeeded()
        return NSFont(name: "Vazirmatn-Regular", size: size)
            ?? NSFont(name: "Vazirmatn", size: size)
            ?? .systemFont(ofSize: size)
    }

    static func vazirmatnFont(size: CGFloat) -> Font {
        registerVazirmatnIfNeeded()
        return .custom("Vazirmatn-Regular", size: size)
    }
}

enum MirookTheme {
    static let appBackground = Color(red: 0.96, green: 0.94, blue: 0.90)
    static let sidebarBackground = Color(red: 0.95, green: 0.93, blue: 0.89)
    static let panelBackground = Color(red: 0.99, green: 0.98, blue: 0.96)
    static let paperBackground = Color.white
    static let readerBackground = Color(red: 0.94, green: 0.92, blue: 0.88)
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.08)
    static let mutedInk = Color(red: 0.44, green: 0.42, blue: 0.39)
    static let faintInk = Color(red: 0.64, green: 0.61, blue: 0.56)
    static let border = Color.black.opacity(0.08)
    static let separator = Color.black.opacity(0.10)
    static let controlFill = Color.white.opacity(0.72)
    static let activeFill = Color(red: 0.07, green: 0.07, blue: 0.07)
    static let disabledFill = Color.black.opacity(0.10)
    static let shadow = Color.black.opacity(0.10)
}

struct MirookMark: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            Path { path in
                path.move(to: CGPoint(x: width * 0.12, y: height * 0.82))
                path.addLine(to: CGPoint(x: width * 0.12, y: height * 0.18))
                path.addLine(to: CGPoint(x: width * 0.50, y: height * 0.56))
                path.addLine(to: CGPoint(x: width * 0.88, y: height * 0.18))
                path.addLine(to: CGPoint(x: width * 0.88, y: height * 0.82))
            }
            .stroke(
                MirookTheme.ink,
                style: StrokeStyle(lineWidth: max(width, height) * 0.08, lineCap: .round, lineJoin: .round)
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct MirookPanelModifier: ViewModifier {
    var padding: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(MirookTheme.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(MirookTheme.border, lineWidth: 1)
            }
    }
}

extension View {
    func mirookPanel(padding: CGFloat = 12) -> some View {
        modifier(MirookPanelModifier(padding: padding))
    }
}

enum MirookDigitNormalizer {
    static func normalizedIntegerText(_ text: String) -> String {
        let mappedScalars = text.unicodeScalars.compactMap { scalar -> Character? in
            switch scalar.value {
            case 0x06F0...0x06F9:
                return Character(String(scalar.value - 0x06F0))
            case 0x0660...0x0669:
                return Character(String(scalar.value - 0x0660))
            case 48...57:
                return Character(scalar)
            default:
                return nil
            }
        }

        return String(mappedScalars)
    }
}

struct MirookNumberField: NSViewRepresentable {
    let placeholder: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step = 1
    var alignment: NSTextAlignment = .center

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, range: range, step: step)
    }

    func makeNSView(context: Context) -> NumberNSTextField {
        let textField = NumberNSTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.alignment = alignment
        textField.isBezeled = false
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 15)
        textField.lineBreakMode = .byClipping
        textField.onStep = { direction in
            context.coordinator.step(direction: direction)
        }
        textField.stringValue = "\(value)"
        return textField
    }

    func updateNSView(_ textField: NumberNSTextField, context: Context) {
        context.coordinator.value = $value
        context.coordinator.range = range
        context.coordinator.stepSize = step
        textField.placeholderString = placeholder
        textField.alignment = alignment
        textField.onStep = { direction in
            context.coordinator.step(direction: direction)
        }

        let valueText = "\(value)"
        if textField.currentEditor() == nil, textField.stringValue != valueText {
            textField.stringValue = valueText
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var value: Binding<Int>
        var range: ClosedRange<Int>
        var stepSize: Int

        init(value: Binding<Int>, range: ClosedRange<Int>, step: Int) {
            self.value = value
            self.range = range
            self.stepSize = step
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            normalize(textField)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            textField.stringValue = "\(value.wrappedValue)"
        }

        func step(direction: Int) {
            let delta = max(stepSize, 1) * direction
            value.wrappedValue = clamped(value.wrappedValue + delta)
        }

        private func normalize(_ textField: NSTextField) {
            let normalized = MirookDigitNormalizer.normalizedIntegerText(textField.stringValue)
            if textField.stringValue != normalized {
                let selectedRange = textField.currentEditor()?.selectedRange
                textField.stringValue = normalized
                if let selectedRange {
                    let location = min(selectedRange.location, normalized.utf16.count)
                    textField.currentEditor()?.selectedRange = NSRange(location: location, length: 0)
                }
            }

            guard !normalized.isEmpty, let integerValue = Int(normalized) else {
                return
            }

            value.wrappedValue = clamped(integerValue)
        }

        private func clamped(_ integerValue: Int) -> Int {
            min(max(integerValue, range.lowerBound), range.upperBound)
        }
    }

    final class NumberNSTextField: NSTextField {
        var onStep: ((Int) -> Void)?

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 126:
                onStep?(1)
            case 125:
                onStep?(-1)
            default:
                super.keyDown(with: event)
            }
        }
    }
}

struct MirookPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.white : MirookTheme.faintInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isEnabled ? MirookTheme.activeFill : MirookTheme.disabledFill)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(configuration.isPressed ? 0.22 : 0.08), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct MirookSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isEnabled ? MirookTheme.ink : MirookTheme.faintInk)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isEnabled ? MirookTheme.controlFill : Color.black.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(MirookTheme.border, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct MirookIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? MirookTheme.ink : MirookTheme.faintInk)
            .frame(width: 32, height: 30)
            .background(isEnabled ? MirookTheme.controlFill : Color.black.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(MirookTheme.border, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
