import AppKit

private let ink = NSColor(calibratedWhite: 0.94, alpha: 1)
private let muted = NSColor(calibratedWhite: 0.62, alpha: 1)
private let amber = NSColor(calibratedRed: 1, green: 0.73, blue: 0.38, alpha: 1)

final class PanelController: NSViewController {
    weak var owner: AppDelegate?
    let stateLabel = NSTextField(labelWithString: "")
    let detailLabel = NSTextField(wrappingLabelWithString: "")
    let temperatureValue = NSTextField(labelWithString: "")
    let brightnessValue = NSTextField(labelWithString: "")
    let temperature = NSSlider(value: 4200, minValue: 2700, maxValue: 6500, target: nil, action: nil)
    let brightness = NSSlider(value: 90, minValue: 30, maxValue: 100, target: nil, action: nil)
    let enabled = NSSwitch()
    let mode = NSSegmentedControl(labels: ["手动调节", "定时调节"], trackingMode: .selectOne, target: nil, action: nil)
    let start = NSDatePicker()
    let end = NSDatePicker()
    let pause = NSButton(title: "暂停 15 分钟", target: nil, action: nil)
    let login = NSButton(checkboxWithTitle: "登录时启动", target: nil, action: nil)
    let scheduleRows = NSStackView()
    let footer = NSTextField(wrappingLabelWithString: "")

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 376, height: 690))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(calibratedRed: 0.075, green: 0.085, blue: 0.10, alpha: 1).cgColor
        root.appearance = NSAppearance(named: .darkAqua)
        view = root
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24)
        ])

        let mark = NSImageView(image: AppImages.sun(size: 36))
        mark.contentTintColor = amber
        mark.widthAnchor.constraint(equalToConstant: 36).isActive = true
        mark.heightAnchor.constraint(equalToConstant: 36).isActive = true
        let titles = NSStackView(views: [label("暮光", size: 24, weight: .semibold), label("让夜晚柔和一点", size: 11, color: muted)])
        titles.orientation = .vertical; titles.alignment = .leading; titles.spacing = 2
        enabled.target = self; enabled.action = #selector(toggleEnabled)
        enabled.setAccessibilityLabel("开启屏幕调节")
        stack.addArrangedSubview(row([mark, titles, spacer(), enabled]))
        stack.addArrangedSubview(separator())

        stateLabel.font = .systemFont(ofSize: 16, weight: .medium); stateLabel.textColor = amber
        detailLabel.font = .systemFont(ofSize: 11); detailLabel.textColor = muted
        detailLabel.maximumNumberOfLines = 3
        detailLabel.heightAnchor.constraint(equalToConstant: 42).isActive = true
        let status = NSStackView(views: [stateLabel, detailLabel])
        status.orientation = .vertical; status.alignment = .leading; status.spacing = 5
        stack.addArrangedSubview(status)

        mode.target = self; mode.action = #selector(modeChanged)
        mode.controlSize = .regular
        stack.addArrangedSubview(mode)

        temperatureValue.textColor = amber
        temperatureValue.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        stack.addArrangedSubview(sliderGroup(title: "暖光色温", value: temperatureValue, slider: temperature,
                                           left: "更暖 · 2700K", right: "自然 · 6500K", action: #selector(temperatureChanged)))
        let presets = row([preset("柔和", kelvin: 5000), preset("暖光", kelvin: 4200), preset("烛光", kelvin: 3000)])
        presets.distribution = .fillEqually
        stack.addArrangedSubview(presets)

        brightnessValue.textColor = ink
        brightnessValue.font = .monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        stack.addArrangedSubview(sliderGroup(title: "画面亮度", value: brightnessValue, slider: brightness,
                                           left: "更暗 · 30%", right: "原始 · 100%", action: #selector(brightnessChanged)))

        for picker in [start, end] {
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = [.hourMinute]
            picker.locale = Locale(identifier: "en_GB")
            picker.target = self; picker.action = #selector(timeChanged)
        }
        start.setAccessibilityLabel("定时开始时间"); end.setAccessibilityLabel("定时结束时间")
        scheduleRows.orientation = .vertical; scheduleRows.alignment = .leading; scheduleRows.spacing = 7
        scheduleRows.addArrangedSubview(row([label("定时时段", size: 12), spacer(), start, label("至", size: 11, color: muted), end]))
        scheduleRows.addArrangedSubview(label("开始后、结束前各用 30 分钟渐变", size: 10, color: muted))
        stack.addArrangedSubview(scheduleRows)
        stack.addArrangedSubview(separator())

        pause.bezelStyle = .rounded; pause.target = self; pause.action = #selector(togglePause)
        let restore = NSButton(title: "恢复原色", target: self, action: #selector(restoreColor))
        restore.bezelStyle = .rounded
        stack.addArrangedSubview(row([pause, spacer(), restore]))
        login.font = .systemFont(ofSize: 11); login.target = self; login.action = #selector(loginChanged)
        let quit = NSButton(title: "退出暮光", target: self, action: #selector(quitApp))
        quit.isBordered = false; quit.font = .systemFont(ofSize: 11)
        stack.addArrangedSubview(row([login, spacer(), quit]))
        footer.font = .systemFont(ofSize: 10); footer.textColor = muted
        footer.maximumNumberOfLines = 3
        footer.stringValue = "首次使用请打开右上角开关。\n画面亮度为软件调暗，不改变屏幕背光。"
        stack.addArrangedSubview(footer)

        for child in stack.arrangedSubviews {
            child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        for child in scheduleRows.arrangedSubviews {
            child.widthAnchor.constraint(equalTo: scheduleRows.widthAnchor).isActive = true
        }
        root.widthAnchor.constraint(equalToConstant: 376).isActive = true
        stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24).isActive = true
    }

    func refresh() {
        guard let owner = owner else { return }
        let p = owner.preferences
        enabled.state = p.enabled ? .on : .off
        mode.selectedSegment = p.scheduled ? 1 : 0
        temperature.doubleValue = p.kelvin; brightness.doubleValue = p.brightness * 100
        temperatureValue.stringValue = "\(Int(p.kelvin)) K"
        brightnessValue.stringValue = "\(Int((p.brightness * 100).rounded()))%"
        for (picker, minutes) in [(start, p.startMinute), (end, p.endMinute)] {
            picker.dateValue = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
            picker.isEnabled = p.scheduled
        }
        scheduleRows.alphaValue = p.scheduled ? 1 : 0.4
        pause.isEnabled = p.enabled
        pause.title = owner.isPaused ? "继续调节" : "暂停 15 分钟"
        login.state = owner.loginEnabled ? .on : .off
        if let message = owner.message {
            stateLabel.stringValue = "需要留意"
            detailLabel.stringValue = message
        } else if !p.enabled {
            stateLabel.stringValue = "原色 · 随时开启"
            detailLabel.stringValue = "打开开关，让屏幕慢慢暖下来。"
        } else if owner.isPaused {
            let minutes = max(1, Int(ceil((owner.pauseUntil?.timeIntervalSinceNow ?? 0) / 60)))
            stateLabel.stringValue = "已暂停 · \(minutes) 分钟后继续"
            detailLabel.stringValue = "当前已恢复开启暮光前的屏幕色彩。"
        } else if p.strength(at: Date()) == 0 {
            stateLabel.stringValue = "白天原色 · 等待夜晚"
            detailLabel.stringValue = "\(Schedule.clock(p.startMinute)) 开始变暖，\(Schedule.clock(p.endMinute)) 恢复原色。"
        } else {
            stateLabel.stringValue = p.scheduled ? "定时暖光已开启" : "暖光已开启"
            detailLabel.stringValue = p.scheduled ? "夜间目标 \(Int(p.kelvin))K · 亮度 \(Int(p.brightness * 100))%\n按设定时段逐渐变化。" : "目标 \(Int(p.kelvin))K · 亮度 \(Int(p.brightness * 100))%\n拖动滑块可随时调整。"
        }
        if owner.loginRequiresApproval {
            footer.stringValue = "登录启动待批准：请到系统设置 → 通用 → 登录项开启。"
        } else {
            footer.stringValue = "画面亮度为软件调暗，不改变屏幕背光。\n建议关闭其他色温工具，避免叠加。"
        }
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = ink) -> NSTextField {
        let field = NSTextField(labelWithString: text); field.font = .systemFont(ofSize: size, weight: weight); field.textColor = color
        return field
    }
    private func spacer() -> NSView { let v = NSView(); v.setContentHuggingPriority(.defaultLow, for: .horizontal); return v }
    private func row(_ children: [NSView]) -> NSStackView {
        let s = NSStackView(views: children); s.orientation = .horizontal; s.alignment = .centerY; s.spacing = 9; return s
    }
    private func separator() -> NSView {
        let v = NSView(); v.wantsLayer = true; v.layer?.backgroundColor = NSColor(white: 1, alpha: 0.09).cgColor
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true; return v
    }
    private func sliderGroup(title: String, value: NSTextField, slider: NSSlider, left: String, right: String, action: Selector) -> NSStackView {
        slider.target = self; slider.action = action; slider.isContinuous = true; slider.controlSize = .regular
        slider.setAccessibilityLabel(title)
        let group = NSStackView(views: [row([label(title, size: 12, weight: .medium), spacer(), value]), slider,
                                        row([label(left, size: 10, color: muted), spacer(), label(right, size: 10, color: muted)])])
        group.orientation = .vertical; group.alignment = .leading; group.spacing = 7
        for child in group.arrangedSubviews { child.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true }
        return group
    }
    private func preset(_ title: String, kelvin: Int) -> NSButton {
        let b = NSButton(title: title, target: self, action: #selector(presetChanged(_:)))
        b.bezelStyle = .rounded; b.tag = kelvin; b.toolTip = "\(kelvin) K"; return b
    }
    @objc private func toggleEnabled() { owner?.update { $0.enabled = enabled.state == .on } }
    @objc private func modeChanged() { owner?.update { $0.scheduled = mode.selectedSegment == 1 } }
    @objc private func temperatureChanged() { owner?.update { $0.kelvin = (temperature.doubleValue / 50).rounded() * 50 } }
    @objc private func brightnessChanged() { owner?.update { $0.brightness = brightness.doubleValue.rounded() / 100 } }
    @objc private func presetChanged(_ sender: NSButton) { owner?.update { $0.kelvin = Double(sender.tag) } }
    @objc private func timeChanged() {
        let c = Calendar.current
        owner?.update { p in
            p.startMinute = c.component(.hour, from: start.dateValue) * 60 + c.component(.minute, from: start.dateValue)
            p.endMinute = c.component(.hour, from: end.dateValue) * 60 + c.component(.minute, from: end.dateValue)
        }
    }
    @objc private func togglePause() { owner?.togglePause() }
    @objc private func restoreColor() { owner?.update { $0.enabled = false } }
    @objc private func loginChanged() { owner?.setLogin(login.state == .on) }
    @objc private func quitApp() { NSApp.terminate(nil) }
}
