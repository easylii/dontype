import CoreAudio
import Foundation
import IOKit

/// CoreAudio 输入设备枚举与查询。
/// 场景：合盖时系统可能把 iPhone（连续互通）设为默认麦克风，导致录到静音。
/// 丝语允许固定使用某个输入设备，不跟系统默认漂移。
enum AudioDevices {
    struct Device {
        let id: AudioDeviceID
        let uid: String
        let name: String
    }

    static func inputDevices() -> [Device] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard inputChannels(id) > 0,
                  let name = stringProp(id, kAudioObjectPropertyName),
                  let uid = stringProp(id, kAudioDevicePropertyDeviceUID) else { return nil }
            return Device(id: id, uid: uid, name: name)
        }
    }

    static func defaultInput() -> Device? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        let name = stringProp(id, kAudioObjectPropertyName) ?? "未知设备"
        let uid = stringProp(id, kAudioDevicePropertyDeviceUID) ?? ""
        return Device(id: id, uid: uid, name: name)
    }

    // MARK: 智能选麦：盖开用内置，合盖用 iPhone（连续互通），都没有则系统默认

    /// MacBook 盖子是否合着（外接显示器 clamshell 模式）
    static func isClamshellClosed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        guard let prop = IORegistryEntryCreateCFProperty(
            service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() else { return false }
        return (prop as? Bool) ?? false
    }

    private static func transportType(_ id: AudioDeviceID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &v) == noErr else { return 0 }
        return v
    }

    static func isBuiltIn(_ id: AudioDeviceID) -> Bool {
        transportType(id) == kAudioDeviceTransportTypeBuiltIn
    }

    /// iPhone/iPad 连续互通麦克风（'ccwd' 有线 / 'ccwl' 无线），兜底按名字匹配
    static func isContinuity(_ id: AudioDeviceID, name: String) -> Bool {
        let t = transportType(id)
        if t == 0x6363_7764 || t == 0x6363_776C { return true }  // 'ccwd' / 'ccwl'
        return name.contains("iPhone") || name.contains("iPad")
    }

    /// 设备分类（驱动药丸里的来源图标）
    static func kind(of d: Device) -> MicSourceKind {
        if isBuiltIn(d.id) { return .builtin }
        if isContinuity(d.id, name: d.name) { return .phone }
        return .external
    }

    /// 选麦：优先用手动指定的 UID（若当前可用），否则回退智能选择。
    /// preferredUID 为空串或对应设备已拔出时，自动走 smartPick。
    static func pick(preferredUID: String) -> (Device, String, MicSourceKind)? {
        if !preferredUID.isEmpty,
           let dev = inputDevices().first(where: { $0.uid == preferredUID }) {
            return (dev, "手动指定", kind(of: dev))
        }
        return smartPick()
    }

    /// 智能选择：返回 (设备, 决策说明, 分类)；无任何输入设备返回 nil
    /// 优先级：盖开内置 → 有线/USB 外接(无提示音) → iPhone 连续互通(每次会 ding) → 系统默认
    static func smartPick() -> (Device, String, MicSourceKind)? {
        let devs = inputDevices()
        let closed = isClamshellClosed()
        // ① 盖子开 → 用内置（无提示音）
        if !closed, let builtin = devs.first(where: { isBuiltIn($0.id) }) {
            return (builtin, "盖子开，用内置", .builtin)
        }
        // ② 有线/USB 外接麦（如摄像头）→ 直连无 ding，优先于 iPhone
        if let wired = devs.first(where: { !isBuiltIn($0.id) && !isContinuity($0.id, name: $0.name) }) {
            return (wired, "外接麦克风（无提示音）", .external)
        }
        // ③ iPhone/iPad 连续互通 → 每次调用会响一声 ding，放后面
        if let phone = devs.first(where: { isContinuity($0.id, name: $0.name) }) {
            return (phone, closed ? "合盖，用 iPhone" : "无内置/外接，用 iPhone", .phone)
        }
        // ④ 兜底：系统默认
        if let def = defaultInput() {
            return (def, "跟随系统默认", kind(of: def))
        }
        return nil
    }

    private static func inputChannels(_ id: AudioDeviceID) -> Int {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let buf = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buf.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, buf) == noErr else { return 0 }
        let list = buf.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func stringProp(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var ref: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        let err = withUnsafeMutablePointer(to: &ref) { ptr in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr)
        }
        guard err == noErr, let s = ref else { return nil }
        return s as String
    }
}
