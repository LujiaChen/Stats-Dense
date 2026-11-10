import Cocoa
import CoreText
import XCTest
@preconcurrency @testable import Kit
@testable import Stats

@MainActor
final class CombinedTests: XCTestCase {
    func testSnapshotDeliveryDeduplicatesAndClearsOnDisable() {
        let menuBar = MenuBar(moduleName: "CombinedSnapshotTests")
        let first = CombinedValues(utilization: 0.09)
        let second = CombinedValues(utilization: 0.10)
        let delivered = expectation(description: "Distinct snapshots delivered on main thread")
        delivered.expectedFulfillmentCount = 2
        delivered.assertForOverFulfill = true
        var received: [CombinedValues] = []
        menuBar.combinedValuesCallback = {
            XCTAssertTrue(Thread.isMainThread)
            received.append(menuBar.combinedValues)
            delivered.fulfill()
        }
        DispatchQueue.global().async {
            menuBar.setCombinedValues(first)
            menuBar.setCombinedValues(first)
            menuBar.setCombinedValues(second)
        }
        wait(for: [delivered], timeout: 2)
        XCTAssertEqual(received, [first, second])
        let cleared = expectation(description: "Disabling clears the cached snapshot")
        menuBar.combinedValuesCallback = {
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(menuBar.combinedValues, CombinedValues())
            cleared.fulfill()
        }
        menuBar.disable()
        wait(for: [cleared], timeout: 2)
        menuBar.combinedValuesCallback = nil
    }

    func testModeLegacyFallbackAndPersistence() {
        let modeExisted = Store.shared.exist(key: "CombinedModules_mode")
        let previousMode = Store.shared.string(key: "CombinedModules_mode", defaultValue: "")
        let iconExisted = Store.shared.exist(key: "CombinedModules_icon")
        let previousIcon = Store.shared.bool(key: "CombinedModules_icon", defaultValue: false)
        defer {
            if modeExisted { Store.shared.set(key: "CombinedModules_mode", value: previousMode) }
            else { Store.shared.remove("CombinedModules_mode") }
            if iconExisted { Store.shared.set(key: "CombinedModules_icon", value: previousIcon) }
            else { Store.shared.remove("CombinedModules_icon") }
        }
        Store.shared.remove("CombinedModules_mode")
        Store.shared.remove("CombinedModules_icon")
        XCTAssertEqual(CombinedModulesMode.current, .normal)
        Store.shared.set(key: "CombinedModules_icon", value: true)
        XCTAssertEqual(CombinedModulesMode.current, .icon)
        Store.shared.set(key: "CombinedModules_mode", value: "invalid-mode")
        XCTAssertEqual(CombinedModulesMode.current, .icon)
        Store.shared.set(key: "CombinedModules_icon", value: false)
        XCTAssertEqual(CombinedModulesMode.current, .normal)
        for mode in [CombinedModulesMode.normal, .dense, .icon] {
            CombinedModulesMode.current = mode
            XCTAssertEqual(CombinedModulesMode.current, mode)
            XCTAssertEqual(Store.shared.string(key: "CombinedModules_mode", defaultValue: ""), mode.rawValue)
            XCTAssertEqual(UserDefaults.standard.string(forKey: "CombinedModules_mode"), mode.rawValue)
            XCTAssertEqual(UserDefaults.standard.bool(forKey: "CombinedModules_icon"), mode == .icon)
        }
        Store.shared.set(key: "CombinedModules_mode", value: "dense")
        Store.shared.set(key: "CombinedModules_icon", value: true)
        XCTAssertEqual(CombinedModulesMode.current, .dense, "A valid mode takes precedence over legacy Icon only")
    }

    func testPercentageBoundariesAndMissingValues() {
        for (value, expected) in [(0.0, "0%"), (0.09, "9%"), (0.10, "10%"), (0.99, "99%"), (1.0, "100%"), (-1.0, "0%"), (2.0, "100%")] {
            XCTAssertEqual(DenseCombinedView.percentage(value), expected)
        }
        for value in [nil, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertEqual(DenseCombinedView.percentage(value), "--%")
            XCTAssertEqual(DenseCombinedView.temperatureText(value), "--°")
            XCTAssertEqual(DenseCombinedView.powerText(value), "--W")
        }
        XCTAssertEqual(DenseCombinedView.powerText(-1), "--W")
    }

    func testTemperatureUnitsAndPowerRounding() {
        let existed = Store.shared.exist(key: "temperature_units")
        let previous = Store.shared.string(key: "temperature_units", defaultValue: "system")
        defer {
            if existed { Store.shared.set(key: "temperature_units", value: previous) }
            else { Store.shared.remove("temperature_units") }
        }
        Store.shared.set(key: "temperature_units", value: "celsius")
        XCTAssertEqual(DenseCombinedView.temperatureText(48), "48°")
        Store.shared.set(key: "temperature_units", value: "fahrenheit")
        XCTAssertEqual(DenseCombinedView.temperatureText(48), "118°")
        let view = DenseCombinedView()
        view.update(cpu: CombinedValues(), gpu: CombinedValues(), memory: CombinedValues(),
                    sensors: CombinedValues(temperature: 48, power: 12.345))
        XCTAssertTrue(view.toolTip?.contains("°F") == true)
        XCTAssertTrue(view.toolTip?.contains("12.35 W") == true)
        for (value, expected) in [(9.0, "9.0W"), (9.95, "10W"), (10.0, "10W"), (99.4, "99W"), (99.5, "100W"),
                                  (999.49, "999W"), (999.5, "1.0kW"), (1234.0, "1.2kW"), (9999.5, "10kW")] {
            XCTAssertEqual(DenseCombinedView.powerText(value), expected)
        }
    }

    func testFixedWidthWorstCaseTextAndHitRegions() {
        let view = DenseCombinedView()
        XCTAssertGreaterThanOrEqual(view.frame.width, 90)
        XCTAssertLessThanOrEqual(view.frame.width, 96, "Keep the compact fixed-width allocation")
        for value in [nil, 0.09, 0.10, 1.0] {
            view.update(cpu: CombinedValues(utilization: value), gpu: CombinedValues(utilization: value),
                        memory: CombinedValues(utilization: value), sensors: CombinedValues(temperature: 100, power: 1000))
            XCTAssertEqual(view.targetWidth, DenseCombinedView.dynamicWidth(view.strings))
            XCTAssertEqual(view.strings.count, 5)
            for cell in view.adaptiveCells() {
                XCTAssertGreaterThanOrEqual(cell.minX, 0)
                XCTAssertLessThanOrEqual(cell.maxX, view.frame.width + 0.001)
            }
        }
        view.update(cpu: CombinedValues(), gpu: CombinedValues(), memory: CombinedValues(), sensors: CombinedValues())
        XCTAssertEqual(view.strings, ["C --%", "G --%", "M --%", "--°", "--W"])
        XCTAssertEqual(view.module(at: NSPoint(x: 0, y: 1)), "Sensors")
        XCTAssertNil(view.hitTest(NSPoint(x: 20, y: 10)))
    }

    func testTextWidthTracksDigitCountWithoutResizingStatusContent() {
        func values(_ percent: String) -> [String] { ["C " + percent, "G " + percent, "M " + percent, "34°", "6.7W"] }
        XCTAssertEqual(DenseCombinedView.dynamicWidth(values("15%")), DenseCombinedView.dynamicWidth(values("30%")))
        XCTAssertLessThan(DenseCombinedView.dynamicWidth(values("9%")), DenseCombinedView.dynamicWidth(values("10%")))
        XCTAssertLessThan(DenseCombinedView.dynamicWidth(values("10%")), DenseCombinedView.dynamicWidth(values("100%")))
        let view = DenseCombinedView()
        let allocated = view.frame.width
        for value in [0.0, 0.09, 0.10, 0.99, 1.0, 0.09] {
            view.update(cpu: CombinedValues(utilization: value), gpu: CombinedValues(utilization: value),
                        memory: CombinedValues(utilization: value), sensors: CombinedValues(temperature: 230, power: 1200))
            XCTAssertEqual(view.frame.width, allocated)
            for cell in view.adaptiveCells() {
                XCTAssertGreaterThanOrEqual(cell.minX, 0)
                XCTAssertLessThanOrEqual(cell.maxX, allocated + 0.001)
            }
        }
    }

    func testFixedRowsHaveEqualLeftAndRightMargins() {
        let view = DenseCombinedView()
        for value in [0.09, 0.23, 1.0] {
            view.update(cpu: CombinedValues(utilization: value), gpu: CombinedValues(utilization: value),
                        memory: CombinedValues(utilization: 0.78), sensors: CombinedValues(temperature: 54, power: 9.5))
            let cells = view.adaptiveCells()
            XCTAssertEqual(cells[0].minX, 0, accuracy: 0.001)
            XCTAssertEqual(cells[2].maxX, view.bounds.width, accuracy: 0.001)
            XCTAssertEqual(cells[0].minX, view.bounds.width - cells[2].maxX, accuracy: 0.001)
            XCTAssertEqual(cells[3].minX, view.bounds.width - cells[4].maxX, accuracy: 0.001)
            let gap = cells[1].minX - cells[0].maxX
            XCTAssertGreaterThanOrEqual(gap + 0.001, 3.9)
            XCTAssertEqual(cells[2].minX - cells[1].maxX, gap, accuracy: 0.001)
            for index in 0..<3 {
                let label = DenseCombinedView.text(String(view.strings[index].prefix(2)), labeled: true)
                let value = DenseCombinedView.text(String(view.strings[index].dropFirst(2)), labeled: false)
                let scale = (cells[index].width - label.size().width) / value.size().width
                XCTAssertGreaterThanOrEqual(scale, 0.74)
                XCTAssertLessThanOrEqual(scale, 1.001)
                if !view.strings.contains(where: { $0.contains("100%") }) {
                    XCTAssertEqual(scale, 1, accuracy: 0.001)
                }
            }
            XCTAssertEqual(cells[4].minX - cells[3].maxX, 6, accuracy: 0.001)
            XCTAssertEqual(view.frame.width, DenseCombinedView.width)
        }
    }

    func testDashboardHierarchyFitsWithoutClippingOrOverlapping() {
        XCTAssertGreaterThanOrEqual(DenseCombinedView.font.pointSize, 13.5)
        let view = DenseCombinedView()
        view.update(cpu: CombinedValues(utilization: 1), gpu: CombinedValues(utilization: 1),
                    memory: CombinedValues(utilization: 1), sensors: CombinedValues(temperature: 230, power: 1234))
        let cells = view.adaptiveCells()
        let strings = ["C 100%", "G 100%", "M 100%", "230°", "1.2kW"]
        for (index, string) in strings.enumerated() {
            let cell = cells[index]
            var runs: [(NSAttributedString, CGFloat, CGFloat)] = []
            if index < 3 {
                let label = DenseCombinedView.text(String(string.prefix(1)) + " ", labeled: true)
                let value = DenseCombinedView.text(String(string.dropFirst(2)), labeled: false)
                let labelFont = label.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                XCTAssertGreaterThanOrEqual(labelFont?.pointSize ?? 0, 9)
                XCTAssertLessThan(labelFont?.pointSize ?? 0, DenseCombinedView.font.pointSize)
                let scale = (cell.width - label.size().width) / value.size().width
                XCTAssertGreaterThanOrEqual(scale, 0.74)
                runs = [(label, cell.minX, 1), (value, cell.minX + label.size().width, scale)]
            } else {
                let value = DenseCombinedView.text(string, labeled: false)
                XCTAssertLessThanOrEqual(value.size().width, cell.width)
                runs = [(value, cell.maxX - value.size().width, 1)]
            }
            for (text, x, scale) in runs {
                let ink = CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(text), [.useGlyphPathBounds])
                XCTAssertGreaterThanOrEqual(x + ink.minX * scale, cell.minX - 0.001)
                XCTAssertLessThanOrEqual(x + ink.maxX * scale, cell.maxX + 0.001)
                XCTAssertGreaterThanOrEqual(cell.minY + 0.5 + ink.minY, cell.minY)
                XCTAssertLessThanOrEqual(cell.minY + 0.5 + ink.maxY, cell.maxY)
            }
        }
        for (index, first) in cells.enumerated() {
            for second in cells.dropFirst(index + 1) {
                XCTAssertFalse(first.intersects(second), "Metric hit regions must not overlap")
            }
        }
    }

    func testThreeColumnGridAndCenteredPhysicalReadings() {
        let columns = DenseCombinedView.cells(height: 22).prefix(3)
        XCTAssertEqual(columns.count, 3)
        for column in columns {
            XCTAssertEqual(column.width, columns.first!.width, accuracy: 0.001)
            XCTAssertEqual(column.midY, 16.5)
        }
        XCTAssertEqual(columns[1].midX - columns[0].midX, columns[2].midX - columns[1].midX, accuracy: 0.001)
        for (temperature, power) in [("9°", "0.1W"), ("34°", "6.7W"), ("230°", "1.2kW"), ("--°", "--W")] {
            let cells = DenseCombinedView.cells(height: 22, temperature: temperature, power: power)
            XCTAssertEqual((cells[3].minX + cells[4].maxX) / 2, DenseCombinedView.width / 2, accuracy: 0.001)
            XCTAssertEqual(cells[4].minX - cells[3].maxX, 6, accuracy: 0.001)
            XCTAssertEqual(cells[3].midY, cells[4].midY)
            XCTAssertGreaterThanOrEqual(cells[3].minX, 0)
            XCTAssertLessThanOrEqual(cells[4].maxX, DenseCombinedView.width)
        }
    }

    func testAllDigitsHaveEqualWidth() {
        let width = DenseCombinedView.text("0", labeled: false).size().width
        for digit in 0...9 {
            XCTAssertEqual(DenseCombinedView.text(String(digit), labeled: false).size().width, width, accuracy: 0.001)
        }
    }

    func testLightAndDarkTextRendering() throws {
        let view = DenseCombinedView()
        view.setFrameSize(NSSize(width: DenseCombinedView.width, height: 22))
        view.update(cpu: CombinedValues(utilization: 1), gpu: CombinedValues(utilization: 1),
                    memory: CombinedValues(utilization: 1), sensors: CombinedValues(temperature: 110, power: 1234))
        var luminances: [Double] = []
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(DenseCombinedView.width * 2), pixelsHigh: 44,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            let scale = NSAffineTransform()
            scale.scale(by: 2)
            scale.concat()
            NSGraphicsContext.current?.compositingOperation = .copy
            NSColor.clear.setFill()
            view.bounds.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            appearance.performAsCurrentDrawingAppearance { view.draw(view.bounds) }
            NSGraphicsContext.restoreGraphicsState()
            let attachment = XCTAttachment(data: try XCTUnwrap(bitmap.representation(using: .png, properties: [:])), uniformTypeIdentifier: "public.png")
            attachment.name = "Dense-\(name.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
            var pixels: [NSColor] = []
            var visiblePixels = Array(repeating: 0, count: 5)
            let regions = view.adaptiveCells()
            var labelRegions: [NSRect] = []
            var valueRegions: [NSRect] = []
            for index in 0..<3 {
                let label = DenseCombinedView.text(String(view.strings[index].prefix(1)) + " ", labeled: true)
                let value = DenseCombinedView.text(String(view.strings[index].dropFirst(2)), labeled: false)
                let origin = regions[index].minX
                labelRegions.append(NSRect(x: origin, y: 11, width: label.size().width, height: 11))
                valueRegions.append(NSRect(x: origin + label.size().width, y: 11, width: regions[index].width - label.size().width, height: 11))
            }
            var labelAlpha: CGFloat = 0
            var valueAlpha: CGFloat = 0
            for y in 0..<44 {
                for x in 0..<Int(DenseCombinedView.width * 2) {
                    if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.1 {
                        pixels.append(color)
                        let point = NSPoint(x: (CGFloat(x) + 0.5) / 2, y: 22 - (CGFloat(y) + 0.5) / 2)
                        if labelRegions.contains(where: { $0.contains(point) }) { labelAlpha = max(labelAlpha, color.alphaComponent) }
                        if valueRegions.contains(where: { $0.contains(point) }) { valueAlpha = max(valueAlpha, color.alphaComponent) }
                        if let region = regions.firstIndex(where: { $0.contains(point) }) {
                            visiblePixels[region] += 1
                        }
                    }
                }
            }
            XCTAssertLessThan(labelAlpha, valueAlpha - 0.1, "Labels should be visually weaker than the readings")
            for (index, count) in visiblePixels.enumerated() {
                XCTAssertGreaterThan(count, 0, "Metric \(index) must render visible strokes in \(name.rawValue)")
            }
            luminances.append(pixels.map { Double(($0.redComponent + $0.greenComponent + $0.blueComponent) / 3) }.reduce(0, +) / Double(max(1, pixels.count)))
        }
        XCTAssertGreaterThan(luminances[1] - luminances[0], 0.5)
    }

    func testLiveReaderSamplesAndActualStatusItemWidths() throws {
        guard ProcessInfo.processInfo.environment["STATS_DENSE_HARDWARE_TEST"] == "1" else {
            throw XCTSkip("Set STATS_DENSE_HARDWARE_TEST=1 on a configured Mac for live reader and menu bar integration validation")
        }
        let names = ["CPU", "GPU", "RAM", "Sensors"]
        let providers = try names.map { name in try XCTUnwrap(modules.first { $0.name == name && $0.enabled }, "Enable \(name) for hardware integration validation") }
        let modeExisted = Store.shared.exist(key: "CombinedModules_mode")
        let previousMode = Store.shared.string(key: "CombinedModules_mode", defaultValue: "")
        let iconExisted = Store.shared.exist(key: "CombinedModules_icon")
        let previousIcon = Store.shared.bool(key: "CombinedModules_icon", defaultValue: false)
        let detailsExisted = Store.shared.exist(key: "CombinedModules_popup")
        let previousDetails = Store.shared.bool(key: "CombinedModules_popup", defaultValue: true)
        defer {
            if modeExisted { Store.shared.set(key: "CombinedModules_mode", value: previousMode) }
            else { Store.shared.remove("CombinedModules_mode") }
            if iconExisted { Store.shared.set(key: "CombinedModules_icon", value: previousIcon) }
            else { Store.shared.remove("CombinedModules_icon") }
            if detailsExisted { Store.shared.set(key: "CombinedModules_popup", value: previousDetails) }
            else { Store.shared.remove("CombinedModules_popup") }
            NotificationCenter.default.post(name: .moduleRearrange, object: nil)
        }
        let deadline = Date().addingTimeInterval(8)
        func readings() -> [Double?] {
            [providers[0].menuBar.combinedValues.utilization, providers[1].menuBar.combinedValues.utilization,
             providers[2].menuBar.combinedValues.utilization, providers[3].menuBar.combinedValues.temperature, providers[3].menuBar.combinedValues.power]
        }
        let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        let dense = try XCTUnwrap(Mirror(reflecting: delegate.combinedView).children.first { $0.label == "denseView" }?.value as? DenseCombinedView)
        let legacyPopup = try XCTUnwrap(Mirror(reflecting: delegate.combinedView).children.first { $0.label == "popup" }?.value as? NSWindow)
        let native = Mirror(reflecting: delegate.combinedView).children.first { $0.label == "nativePopover" }?.value as? NSPopover
        var popup: NSWindow { native?.contentViewController?.view.window ?? legacyPopup }
        let popupWasVisible = native?.isShown ?? legacyPopup.isVisible
        defer { if native != nil { native?.close() } else { legacyPopup.setIsVisible(popupWasVisible) } }
        Store.shared.set(key: "CombinedModules_popup", value: true)
        func contains(_ root: NSView, descendant: NSView) -> Bool {
            root === descendant || root.subviews.contains { contains($0, descendant: descendant) }
        }
        let originalCallbacks = providers.map { $0.menuBar.combinedValuesCallback }
        var lastValues = readings()
        var changes = Array(repeating: 0, count: 5)
        for (index, provider) in providers.enumerated() {
            provider.menuBar.combinedValuesCallback = {
                originalCallbacks[index]?()
                let values = readings()
                for metric in values.indices where values[metric] != lastValues[metric] { changes[metric] += 1 }
                lastValues = values
            }
        }
        defer { for (index, provider) in providers.enumerated() { provider.menuBar.combinedValuesCallback = originalCallbacks[index] } }
        CombinedModulesMode.current = .dense
        NotificationCenter.default.post(name: .moduleRearrange, object: nil)
        while readings().contains(where: { $0 == nil }) && deadline.timeIntervalSinceNow > 0 { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
        for index in 0..<3 {
            let values = readings()
            XCTAssertEqual(values.compactMap { $0 }.filter { $0.isFinite }.count, 5, "All five live metrics must be available")
            XCTAssertEqual(dense.frame.width, DenseCombinedView.width, "Live readings must not resize Dense")
            print("DENSE_LIVE \(index) \(Date()) CPU/GPU/RAM/temp/power=\(values) displayed=\(dense.strings)")
            XCTAssertEqual(dense.strings, ["C " + DenseCombinedView.percentage(values[0]), "G " + DenseCombinedView.percentage(values[1]),
                "M " + DenseCombinedView.percentage(values[2]), DenseCombinedView.temperatureText(values[3]), DenseCombinedView.powerText(values[4])])
            if index < 2 { RunLoop.main.run(until: Date().addingTimeInterval(2)) }
        }
        print("DENSE_LIVE_CHANGED CPU/GPU/RAM/temp/power=\(changes); zero means no value change observed during this sample window")
        var popupOccluded = false
        for mode in [CombinedModulesMode.normal, .dense, .icon] {
            CombinedModulesMode.current = mode
            NotificationCenter.default.post(name: .moduleRearrange, object: nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            let item = try XCTUnwrap(Mirror(reflecting: delegate.combinedView).children.first { $0.label == "menuBarItem" }?.value as? NSStatusItem)
            print("DENSE_WIDTH \(mode.rawValue) length=\(item.length) button=\(String(describing: item.button?.frame.width)) window=\(String(describing: item.button?.window?.frame.width)) height=\(String(describing: item.button?.bounds.height))")
            XCTAssertGreaterThan(item.length, 0)
            if mode == .dense && modules.allSatisfy({ !$0.enabled || $0.menuBar.activeWidgets.isEmpty || DenseCombinedView.moduleNames.contains($0.name) }) {
                XCTAssertEqual(item.length, dense.frame.width)
            }
            let button = try XCTUnwrap(item.button)
            if mode == .dense, let bitmap = button.bitmapImageRepForCachingDisplay(in: button.bounds) {
                bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
                button.cacheDisplay(in: button.bounds, to: bitmap)
                let attachment = XCTAttachment(data: try XCTUnwrap(bitmap.representation(using: .png, properties: [:])), uniformTypeIdentifier: "public.png")
                attachment.name = "Dense-ActualStatusButton"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            native?.close()
            legacyPopup.setIsVisible(false)
            NSApp.activate(ignoringOtherApps: true)
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            button.performClick(nil)
            let visibleDeadline = Date().addingTimeInterval(2)
            while !popup.occlusionState.contains(.visible) && visibleDeadline.timeIntervalSinceNow > 0 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            print("DENSE_POPUP_FRAME \(mode.rawValue) item=\(String(describing: button.window?.frame)) popup=\(popup.frame) visible=\(popup.isVisible) occlusion=\(popup.occlusionState.rawValue)")
            XCTAssertTrue(popup.isVisible, "\(mode.rawValue) must open the existing Combined popup")
            let content = try XCTUnwrap(popup.contentView)
            let activePortals = modules.filter { $0.enabled && $0.portal != nil }
            for module in activePortals {
                XCTAssertTrue(contains(content, descendant: try XCTUnwrap(module.portal)), "Combined popup must retain \(module.name)")
            }
            print("DENSE_POPUP \(mode.rawValue) visible=\(popup.isVisible) portals=\(activePortals.map { $0.name })")
            guard popup.occlusionState.contains(.visible) else {
                // Upstream toggles an occluded popup by bringing it forward;
                // an interactive desktop is required to test the closing click.
                popupOccluded = true
                print("DENSE_POPUP_CLOSE_SKIPPED \(mode.rawValue): WindowServer reports the popup fully occluded")
                native?.close()
                legacyPopup.setIsVisible(false)
                continue
            }
            button.performClick(nil)
            let hiddenDeadline = Date().addingTimeInterval(2)
            while popup.isVisible && hiddenDeadline.timeIntervalSinceNow > 0 {
                RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            }
            print("DENSE_POPUP_CLOSED \(mode.rawValue) closed=\(!popup.isVisible)")
            XCTAssertFalse(popup.isVisible, "\(mode.rawValue) must close the Combined popup on the second click")
        }
        if popupOccluded {
            throw XCTSkip("Live metrics, widths and popup content were checked; closing-click validation needs an unoccluded desktop")
        }
    }
}
