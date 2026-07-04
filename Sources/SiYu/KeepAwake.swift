import AppKit
import IOKit.ps

/// 「保持唤醒」（类 Amphetamine）：阻止系统休眠，让合盖 / 电池时也保持联网。
///
/// 机制：Apple Silicon 上唯一能做到「电池 + 合盖不睡」的只有 root 级 `pmset -a disablesleep 1`
/// （IOPMAssertion / caffeinate -s 的 PreventSystemSleep 官方文档写明「仅插电有效」，挡不住电池闭盖）。
/// 为了能静默开关（尤其定时到点 / 电池到阈值要自动关，那时可能正合着盖、看不到密码框），
/// 首次开启时用系统管理员授权装一条**只允许切 disablesleep**的 sudoers 白名单，之后全部静默。
final class KeepAwake {
    enum Mode: Equatable {
        case off
        case timed(minutes: Int, until: Date)   // 定时（显示倒计时）
        case indefinite                         // 一直开（到电池阈值自动关）
    }
    private(set) var mode: Mode = .off
    var isOn: Bool { mode != .off }

    /// 状态变化（开/关/自动关）→ 刷新菜单
    var onChange: (() -> Void)?
    /// 菜单栏倒计时文本（nil = 清空）
    var onTick: ((String?) -> Void)?
    /// 自动关闭（定时到点 / 电池到阈值）→ 上层弹一条提示
    var onAutoOff: ((String) -> Void)?

    private let batteryFloor = 15      // 电池 ≤ 此值（且在用电池）自动关，安全兜底
    private var timer: Timer?
    private var tickCount = 0
    private var lastText: String?

    private static let sudoersPath = "/etc/sudoers.d/dontype-keepawake"

    // MARK: 开 / 关

    /// minutes = nil → 一直开；否则定时。授权/切换在后台线程做（osascript 密码框会阻塞）。
    func start(minutes: Int?) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if !self.setDisableSleep(true) {                 // 先试静默
                guard self.installSudoers() else {           // 失败 = 还没授权 → 装白名单（弹一次密码框）
                    DispatchQueue.main.async { FileLog.write("保持唤醒：授权失败或被取消"); self.onChange?() }
                    return
                }
                guard self.setDisableSleep(true) else {
                    DispatchQueue.main.async { FileLog.write("保持唤醒：授权后仍无法开启"); self.onChange?() }
                    return
                }
            }
            DispatchQueue.main.async {
                if let m = minutes {
                    self.mode = .timed(minutes: m, until: Date().addingTimeInterval(Double(m * 60)))
                    FileLog.write("保持唤醒：开启，定时 \(m) 分钟")
                } else {
                    self.mode = .indefinite
                    FileLog.write("保持唤醒：开启，一直开（到电池 \(self.batteryFloor)%）")
                }
                self.startTimer()
                self.onChange?()
            }
        }
    }

    func stop() {
        let wasOn = isOn
        mode = .off
        timer?.invalidate(); timer = nil
        lastText = nil
        onTick?(nil)
        onChange?()
        if wasOn {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                if self?.setDisableSleep(false) == true { FileLog.write("保持唤醒：已关闭") }
                else { FileLog.write("保持唤醒：关闭 disablesleep 失败") }
            }
        }
    }

    /// 定时模式的剩余时间文本（非定时 = nil）；给菜单标题快照用。
    var remainingText: String? {
        if case .timed(_, let until) = mode { return KeepAwake.format(until.timeIntervalSinceNow) }
        return nil
    }
    /// 当前选中的预设分钟数（定时）；一直开 = 0；关闭 = nil。给菜单打勾用。
    var selectedTag: Int? {
        switch mode {
        case .off: return nil
        case .indefinite: return 0
        case .timed(let m, _): return m
        }
    }

    // MARK: 计时 + 电池兜底

    private func startTimer() {
        timer?.invalidate()
        tickCount = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        tick()   // 立刻显示一次
    }

    private func tick() {
        tickCount += 1
        // 每 10s 查一次电池：在用电池且 ≤ 阈值 → 自动关（无论定时/一直开），防走开后耗干
        if tickCount % 10 == 0, let b = KeepAwake.batteryInfo(), !b.onAC, b.pct <= batteryFloor {
            FileLog.write("保持唤醒：电池 \(b.pct)% ≤ \(batteryFloor)%，自动关闭")
            onAutoOff?("电池 \(b.pct)%，已关闭保持唤醒")
            stop(); return
        }
        switch mode {
        case .timed(_, let until):
            let rem = until.timeIntervalSinceNow
            if rem <= 0 { FileLog.write("保持唤醒：定时到点，自动关闭"); onAutoOff?("定时结束，已关闭保持唤醒"); stop(); return }
            emit(KeepAwake.format(rem))
        case .indefinite:
            emit("∞")
        case .off:
            emit(nil)
        }
    }

    private func emit(_ t: String?) { if t != lastText { lastText = t; onTick?(t) } }

    static func format(_ secs: TimeInterval) -> String {
        let s = max(0, Int(secs.rounded()))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// 电池百分比 + 是否插电（IOKit Power Sources）。
    static func batteryInfo() -> (pct: Int, onAC: Bool)? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  let cur = d[kIOPSCurrentCapacityKey] as? Int else { continue }
            let mx = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let state = d[kIOPSPowerSourceStateKey] as? String ?? ""
            let pct = mx > 0 ? Int((Double(cur) / Double(mx) * 100).rounded()) : cur
            return (pct, state == kIOPSACPowerValue)
        }
        return nil
    }

    // MARK: root 授权 + 切换

    /// `sudo -n pmset -a disablesleep 0/1`（-n = 不弹密码，靠白名单静默）。
    @discardableResult
    private func setDisableSleep(_ on: Bool) -> Bool {
        let p = Process()
        p.launchPath = "/usr/bin/sudo"
        p.arguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", on ? "1" : "0"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// 首次：弹一次系统管理员授权框，装一条只允许切 disablesleep 的 sudoers 白名单。
    /// 用 visudo -cf 先校验语法，通过才安装 —— 绝不写坏 sudoers 把 sudo 弄挂。
    private func installSudoers() -> Bool {
        let user = NSUserName()
        let rule = "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n"
        let tmp = NSTemporaryDirectory() + "dontype-keepawake.rule"
        do { try rule.write(toFile: tmp, atomically: true, encoding: .utf8) } catch {
            FileLog.write("保持唤醒：写临时规则失败 \(error)"); return false
        }
        let shell = "/usr/sbin/visudo -cf '\(tmp)'"
            + " && /bin/cp '\(tmp)' '\(Self.sudoersPath)'"
            + " && /bin/chmod 440 '\(Self.sudoersPath)'"
            + " && /usr/sbin/chown root:wheel '\(Self.sudoersPath)'"
            + " && /bin/rm -f '\(tmp)'"
        return runAsAdmin(shell)
    }

    /// 通过 osascript 触发系统「管理员授权」对话框执行一段 shell。
    private func runAsAdmin(_ shell: String) -> Bool {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let p = Process()
        p.launchPath = "/usr/bin/osascript"
        p.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
        let errPipe = Pipe(); p.standardError = errPipe
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let msg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            FileLog.write("保持唤醒：安装白名单失败：\(msg.prefix(200))")
        }
        return p.terminationStatus == 0
    }
}
