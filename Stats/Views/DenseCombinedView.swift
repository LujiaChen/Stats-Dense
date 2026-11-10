//
//  DenseCombinedView.swift
//  Stats
//
//  A fixed-width presentation of the existing module samples. No sampling here.
//

import Cocoa
import CoreText
import Kit

internal final class DenseCombinedView: NSView {
    // Keep a compact, fixed allocation for ordinary readings. The occasional
    // three-digit reading fits in place without resizing the system menu bar.
    static let width: CGFloat = dynamicWidth(["C 99%", "G 99%", "M 99%", "230°", "1.2kW"]) - 1
    static let moduleNames: Set<String> = ["CPU", "GPU", "RAM", "Sensors"]
    static let font = makeFont(size: 13.5, weight: .semibold)
    private static let labelFont = makeFont(size: 9.5, weight: .medium)
    private static let unitFont = makeFont(size: 11.5, weight: .medium)
    private static let digitWidths = (0...9).map {
        NSAttributedString(string: String($0), attributes: [.font: DenseCombinedView.font, .kern: 0]).size().width
    }
    private static let digitAdvance = digitWidths.max() ?? 0
    private static let inset: CGFloat = 0
    private static let columnGap: CGFloat = 1.5
    private static let labelGap: CGFloat = 0.75
    private static let footerGap: CGFloat = 6
    private static let labelSpaceWidth = NSAttributedString(string: " ", attributes: [.font: DenseCombinedView.labelFont, .kern: 0]).size().width

    private struct TextRun {
        let line: CTLine
        let width: CGFloat
        init(_ text: NSAttributedString) {
            line = CTLineCreateWithAttributedString(text)
            width = text.size().width
        }
    }
    private static let labels = ["C ", "G ", "M "].map { TextRun(text($0, labeled: true)) }
    private var values: [TextRun] = []
    private var textWidths: [CGFloat] = []

    // Intrinsic text-block width, used only to position the existing rows.
    private(set) var targetWidth: CGFloat = DenseCombinedView.width
    private(set) var strings = ["C --%", "G --%", "M --%", "--°", "--W"]

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Constants.Widget.height))
        self.wantsLayer = true
        self.rebuildTextCache()
        self.setAccessibilityElement(true)
        self.setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(cpu: CombinedValues, gpu: CombinedValues, memory: CombinedValues, sensors: CombinedValues) {
        let strings = [
            "C " + Self.percentage(cpu.utilization),
            "G " + Self.percentage(gpu.utilization),
            "M " + Self.percentage(memory.utilization),
            Self.temperatureText(sensors.temperature),
            Self.powerText(sensors.power)
        ]
        let temperatureDetail = sensors.temperature.flatMap { $0.isFinite ? temperature($0) : nil } ?? "--"
        let powerDetail = sensors.power.flatMap { $0.isFinite && $0 >= 0 ? String(format: "%.2f W", $0) : nil } ?? "--"
        let description = [
            "CPU: \(strings[0].dropFirst(2))", "GPU: \(strings[1].dropFirst(2))", "RAM: \(strings[2].dropFirst(2))",
            "\(localizedString(sensors.temperatureLabel ?? "Temperature")): \(temperatureDetail)",
            "\(localizedString(sensors.powerLabel ?? "System Total")): \(powerDetail)"
        ].joined(separator: ", ")
        self.toolTip = description
        self.setAccessibilityLabel(description)
        guard self.strings != strings else { return }
        self.strings = strings
        self.rebuildTextCache()
        self.targetWidth = Self.measuredWidth(self.textWidths)
        self.needsDisplay = true
    }

    static func percentage(_ value: Double?) -> String {
        guard let value = value, value.isFinite else { return "--%" }
        return "\(Int((min(1, max(0, value)) * 100).rounded()))%"
    }

    static func temperatureText(_ value: Double?) -> String {
        guard let value = value, value.isFinite else { return "--°" }
        // As in Stats' sensor mini format, the degree sign is enough in the bar;
        // the existing unit preference and the full unit remain in the tooltip.
        return temperature(value).replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "C", with: "").replacingOccurrences(of: "F", with: "")
    }

    static func powerText(_ value: Double?) -> String {
        guard let value = value, value.isFinite, value >= 0 else { return "--W" }
        if value < 9.95 { return String(format: "%.1fW", value) }
        if value < 999.5 { return String(format: "%.0fW", value) }
        if value < 9999.5 { return String(format: "%.1fkW", value / 1000) }
        return String(format: "%.0fkW", value / 1000)
    }

    // Three equal columns above an optically centered pair of physical readings.
    static func cells(height: CGFloat, temperature: String = "230°", power: String = "1.2kW") -> [NSRect] {
        let offset = (height - 22) / 2
        let columnWidth = (Self.width - Self.inset * 2 - Self.columnGap * 2) / 3
        var cells = (0..<3).map { index in
            NSRect(x: Self.inset + CGFloat(index) * (columnWidth + Self.columnGap), y: offset + 11, width: columnWidth, height: 11)
        }
        let temperatureWidth = Self.text(temperature, labeled: false).size().width
        let powerWidth = Self.text(power, labeled: false).size().width
        let origin = (Self.width - temperatureWidth - Self.footerGap - powerWidth) / 2
        cells.append(NSRect(x: origin, y: offset, width: temperatureWidth, height: 11))
        cells.append(NSRect(x: origin + temperatureWidth + Self.footerGap, y: offset, width: powerWidth, height: 11))
        return cells
    }

    // Size each group to its rendered text; digits are tabular so width changes
    // only when a reading gains or loses a character.
    private static let adaptiveGap: CGFloat = 4
    static func dynamicWidth(_ strings: [String]) -> CGFloat {
        measuredWidth(strings.enumerated().map { text($0.element, labeled: $0.offset < 3).size().width })
    }

    private static func measuredWidth(_ widths: [CGFloat]) -> CGFloat {
        let upper = widths.prefix(3).reduce(0, +) + adaptiveGap * 2
        let lower = widths[3] + footerGap + widths[4]
        return ceil(max(upper, lower) + inset * 2)
    }

    private func rebuildTextCache() {
        // Reader delivery, rather than each animation frame or status-item
        // snapshot, is the only time text shaping and measurement are needed.
        values = strings.enumerated().map { index, string in
            TextRun(Self.text(index < 3 ? String(string.dropFirst(2)) : string, labeled: false))
        }
        textWidths = strings.enumerated().map { Self.text($0.element, labeled: $0.offset < 3).size().width }
    }

    private var valueScale: CGFloat {
        guard strings.prefix(3).contains(where: { $0.hasSuffix("100%") }) else { return 1 }
        let labels = Self.labels.reduce(CGFloat(0)) { $0 + $1.width }
        let numbers = values.prefix(3).reduce(CGFloat(0)) { $0 + $1.width }
        return min(1, (bounds.width - Self.adaptiveGap * 2 - labels) / numbers)
    }

    func adaptiveCells() -> [NSRect] {
        let offset = (bounds.height - 22) / 2
        // Keep each label attached to its value. The fixed allocation's spare
        // space belongs between groups, never inside a group or outside it.
        let scale = valueScale
        let widths = (0..<3).map { Self.labels[$0].width + values[$0].width * scale }
        let gap = (bounds.width - widths.reduce(0, +)) / 2
        var x: CGFloat = 0
        var result: [NSRect] = []
        for width in widths {
            result.append(NSRect(x: x, y: offset + 11, width: width, height: 11))
            x += width + gap
        }
        let t = textWidths[3]
        let p = textWidths[4]
        let start = (bounds.width - t - Self.footerGap - p) / 2
        result.append(NSRect(x: start, y: offset, width: t, height: 11))
        result.append(NSRect(x: start + t + Self.footerGap, y: offset, width: p, height: 11))
        return result
    }

    func module(at point: NSPoint) -> String {
        guard point.y >= self.bounds.midY else { return "Sensors" }
        let columns = self.adaptiveCells().prefix(3)
        let index = columns.firstIndex(where: { point.x < $0.maxX + Self.columnGap / 2 }) ?? 2
        return ["CPU", "GPU", "RAM"][index]
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil // Keep the native status-item button's left/right click behavior.
    }

    private static func makeFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base: NSFont
        if #available(macOS 13.0, *) {
            base = NSFont.systemFont(ofSize: size, weight: weight, width: .condensed)
        } else {
            base = NSFont(name: "HelveticaNeue-CondensedBold", size: size)
                ?? NSFont.monospacedSystemFont(ofSize: size * 0.75, weight: weight)
        }
        let descriptor = base.fontDescriptor.addingAttributes([.featureSettings: [
            [NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
             NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]
        ]])
        return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
    }

    static func text(_ string: String, labeled: Bool) -> NSAttributedString {
        let text = NSMutableAttributedString(string: string, attributes: [
            .font: Self.font, .kern: 0,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true
        ])
        if labeled {
            text.addAttribute(.font, value: Self.labelFont, range: NSRange(location: 0, length: 2))
            text.addAttribute(.kern, value: Self.labelGap - Self.labelSpaceWidth, range: NSRange(location: 1, length: 1))
        }
        for (index, character) in string.enumerated() {
            let range = NSRange(location: index, length: 1)
            if let digit = character.asciiValue, digit >= 48, digit <= 57 {
                // Keep tabular advances even on condensed font versions whose
                // width axis gives the number glyphs slightly different advances.
                text.addAttribute(.kern, value: Self.digitAdvance - Self.digitWidths[Int(digit - 48)], range: range)
            } else if character == "%" {
                text.addAttribute(.font, value: Self.labelFont, range: range)
            } else if (!labeled || index >= 2) && "°Wk".contains(character) {
                text.addAttribute(.font, value: Self.unitFont, range: range)
            }
        }
        return text
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.textMatrix = .identity
        context.setTextDrawingMode(.fill)
        let cells = self.adaptiveCells()
        for index in self.strings.indices {
            let cell = cells[index]
            let baseline = cell.minY + 0.5
            func drawText(_ run: TextRun, x: CGFloat, secondary: Bool = false, scale: CGFloat = 1) {
                context.saveGState()
                context.setFillColor((secondary ? NSColor.labelColor.withAlphaComponent(0.60) : NSColor.labelColor).cgColor)
                context.translateBy(x: x, y: baseline)
                context.scaleBy(x: scale, y: 1)
                context.textPosition = .zero
                CTLineDraw(run.line, context)
                context.restoreGState()
            }
            if index < 3 {
                let label = Self.labels[index]
                let value = self.values[index]
                drawText(label, x: cell.minX, secondary: true)
                drawText(value, x: cell.minX + label.width, scale: valueScale)
            } else {
                let value = self.values[index]
                drawText(value, x: cell.minX)
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.needsDisplay = true
    }
}
