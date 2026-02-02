//
//  ContentView.swift
//  USB - Ultra USB Inspector
//
//  Created by Gunnar Hostetler on 1/30/26.
//

import Combine
import IOKit
import IOKit.usb
import SwiftUI

// MARK: - IOKit USB Constants
let kUSBVendorID = "idVendor"
let kUSBProductID = "idProduct"
let kUSBVendorString = "USB Vendor Name"
let kUSBProductString = "USB Product Name"
let kUSBSerialNumberString = "USB Serial Number"
let kUSBDeviceSpeed = "Device Speed"
let kUSBDeviceClass = "bDeviceClass"
let kUSBDeviceSubClass = "bDeviceSubClass"
let kUSBDeviceProtocol = "bDeviceProtocol"
let kUSBMaxPower = "bMaxPower"
let kUSBDevicePropertyLocationID = "locationID"

// MARK: - USB Device Class Descriptions (with layman explanations)
let usbClassDescriptions: [Int: (name: String, description: String, icon: String, layman: String)] = [
    0: ("Multi-Function", "Composite device with multiple features", "square.stack.3d.up", "This device does several things at once (like a webcam with a built-in microphone)"),
    1: ("Audio Device", "Sound input/output device", "speaker.wave.2", "Plays or records sound – like speakers, headphones, or a microphone"),
    2: ("Network/Serial", "Communications adapter", "network", "Connects to networks or other devices – like a USB ethernet adapter or modem"),
    3: ("Input Device", "Keyboard, mouse, or controller", "keyboard", "Something you use to control your computer – keyboard, mouse, game controller, etc."),
    5: ("Haptic Device", "Force feedback controller", "gamecontroller", "A controller that vibrates or pushes back, like a rumble gamepad"),
    6: ("Camera/Scanner", "Image capture device", "camera", "Captures photos or scans documents – like a camera or flatbed scanner"),
    7: ("Printer", "Printing device", "printer", "Prints documents or images on paper"),
    8: ("Storage", "Data storage device", "externaldrive", "Stores your files – USB drives, external hard drives, SD card readers"),
    9: ("USB Hub", "Port expander", "arrow.triangle.branch", "Adds more USB ports to your computer – plug in multiple devices"),
    10: ("Data Transfer", "Raw data channel", "waveform", "Transfers raw data for network or serial connections"),
    11: ("Smart Card Reader", "Security card reader", "creditcard", "Reads security cards for authentication or payments"),
    13: ("Biometric", "Security scanner", "touchid", "Scans fingerprints or other biometric data for security"),
    14: ("Webcam", "Video capture device", "video", "Records video – webcams, capture cards, video cameras"),
    15: ("Health Device", "Medical sensor", "heart.text.square", "Monitors health – like a heart rate monitor or glucose meter"),
    16: ("A/V Device", "Audio/video combo device", "video.badge.waveform", "Handles both audio and video together – like a webcam with microphone"),
    17: ("USB-C Info", "Capability advertisement", "info.circle", "Tells your computer what this USB-C port/device can do"),
    18: ("USB-C Bridge", "Connection bridge", "point.3.connected.trianglepath.dotted", "Converts or bridges different connection types through USB-C"),
    220: ("Test Device", "Diagnostic tool", "wrench.and.screwdriver", "Used for testing and troubleshooting USB connections"),
    224: ("Wireless Adapter", "Bluetooth/wireless", "wifi", "Adds wireless capabilities – like a Bluetooth dongle or wireless adapter"),
    239: ("Misc Device", "General purpose", "ellipsis.circle", "A general-purpose device that doesn't fit other categories"),
    254: ("Special Purpose", "Application-specific", "wrench", "Designed for a specific app or purpose"),
    255: ("Custom Device", "Manufacturer-specific", "shippingbox", "Uses the manufacturer's own special features")
]

// MARK: - USB Controller Model
struct USBController: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let className: String
    let locationID: UInt32
    let busPowerAvailable: Int
    let isBuiltIn: Bool
    let controllerType: String
    let pciInfo: String
    let supportsUSB3: Bool
    let rawProperties: [String: String]

    var powerDescription: String {
        if busPowerAvailable > 0 {
            return "\(busPowerAvailable) mA available (\(Double(busPowerAvailable) * 5.0 / 1000.0) W @ 5V)"
        }
        return "Bus powered"
    }
}

// MARK: - Thunderbolt Device Model
struct ThunderboltDevice: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let vendorName: String
    let deviceName: String
    let uid: String
    let routeString: String
    let linkSpeed: Int // Gbps
    let linkWidth: Int
    let generation: Int
    let isConnected: Bool
    let rawProperties: [String: String]

    var generationString: String {
        switch generation {
        case 1: return "Thunderbolt 1"
        case 2: return "Thunderbolt 2"
        case 3: return "Thunderbolt 3"
        case 4: return "Thunderbolt 4"
        case 5: return "Thunderbolt 5"
        default: return "Thunderbolt"
        }
    }

    var speedDescription: String {
        if linkSpeed > 0 {
            return "\(linkSpeed) Gbps × \(linkWidth) lanes"
        }
        switch generation {
        case 1: return "10 Gbps (bi-directional)"
        case 2: return "20 Gbps (bi-directional)"
        case 3, 4: return "40 Gbps (bi-directional)"
        case 5: return "80-120 Gbps (bi-directional)"
        default: return "Unknown"
        }
    }

    var color: Color {
        switch generation {
        case 1, 2: return .blue
        case 3: return .purple
        case 4: return .indigo
        case 5: return .pink
        default: return .gray
        }
    }
}

// MARK: - USB Device Model
struct USBDevice: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let vendorID: Int
    let productID: Int
    let vendorName: String
    let productName: String
    let serialNumber: String
    let speed: USBSpeed
    let deviceClass: Int
    let deviceSubClass: Int
    let deviceProtocol: Int
    let maxPower: Int
    let usbVersion: String
    let locationID: UInt32
    let isHub: Bool
    let portCount: Int

    // Extended properties
    let bcdDevice: Int
    let currentAvailable: Int
    let extraCurrentInSleep: Int
    let busPowerAvailable: Int
    let isCaptive: Bool
    let isInternal: Bool
    let sleepCurrent: Int
    let sessionID: UInt64
    let portType: String
    let parentControllerName: String
    let rawProperties: [String: String]

    var vendorIDHex: String { String(format: "0x%04X", vendorID) }
    var productIDHex: String { String(format: "0x%04X", productID) }

    var bcdDeviceString: String {
        if bcdDevice > 0 {
            let major = (bcdDevice >> 8) & 0xFF
            let minor = (bcdDevice >> 4) & 0x0F
            let patch = bcdDevice & 0x0F
            return "\(major).\(minor)\(patch > 0 ? ".\(patch)" : "")"
        }
        return "N/A"
    }

    var powerDescription: String {
        if maxPower > 0 {
            let watts = Double(maxPower) * 5.0 / 1000.0
            return "\(maxPower) mA (\(String(format: "%.2f", watts)) W @ 5V)"
        }
        return "N/A"
    }

    var powerAvailableDescription: String {
        if busPowerAvailable > 0 {
            return "\(busPowerAvailable) mA available"
        } else if currentAvailable > 0 {
            return "\(currentAvailable) mA available"
        }
        return "Standard bus power"
    }

    var classInfo: (name: String, description: String, icon: String, layman: String) {
        usbClassDescriptions[deviceClass] ?? ("Unknown Type", "Unrecognized device class", "questionmark.circle", "We couldn't identify what type of device this is")
    }

    var theoreticalBandwidth: (speed: String, practical: String, realWorld: String) {
        switch speed {
        case .low: return ("1.5 Mbps", "~0.19 MB/s", "Basic keyboards and mice – very slow by today's standards")
        case .full: return ("12 Mbps", "~1.5 MB/s", "Old USB 1.1 – a 1GB file would take ~11 minutes")
        case .high: return ("480 Mbps", "~40-50 MB/s", "Standard USB 2.0 – a 1GB file takes ~20 seconds")
        case .super_: return ("5 Gbps", "~400-450 MB/s", "Fast USB 3.0 – a 1GB file takes ~2-3 seconds")
        case .superPlus: return ("10 Gbps", "~900-1000 MB/s", "Very fast – a 1GB file in about 1 second")
        case .superPlusBy2: return ("20 Gbps", "~2000 MB/s", "Blazing fast – a 4K movie in seconds")
        case .unknown: return ("Unknown", "N/A", "Speed couldn't be determined")
        }
    }

    var connectionQuality: (rating: String, score: Int, color: Color, issues: [String], summary: String) {
        var score = 100
        var issues: [String] = []

        if speed == .unknown {
            score -= 40
            issues.append("⚠️ Can't detect speed – try a different port or cable")
        }

        if maxPower > 0 && busPowerAvailable > 0 && maxPower > busPowerAvailable {
            score -= 25
            issues.append("🔌 Needs more power than the port provides – device may not work properly or charge slowly")
        }

        if vendorID == 0 && productID == 0 {
            score -= 20
            issues.append("❓ Device didn't identify itself – could be a cheap/counterfeit cable or device")
        }

        if serialNumber.isEmpty && !isHub {
            score -= 5
            issues.append("ℹ️ No serial number – minor issue, won't affect performance")
        }

        let rating: String
        let color: Color
        let summary: String

        if score >= 90 {
            rating = "Excellent"
            color = .green
            summary = "Everything looks great! This device is working at its best."
        } else if score >= 70 {
            rating = "Good"
            color = .yellow
            summary = "Working fine with minor notes. Should perform well for most uses."
        } else if score >= 50 {
            rating = "Fair"
            color = .orange
            summary = "Some issues detected. The device may not perform optimally."
        } else {
            rating = "Poor"
            color = .red
            summary = "Significant problems found. Consider using a different port, cable, or device."
        }

        return (rating, score, color, issues.isEmpty ? ["✅ All systems go – device is working perfectly"] : issues, summary)
    }

    var locationDescription: String {
        // Decode location ID into port path
        var path: [Int] = []
        var loc = locationID >> 20 // Skip controller bits
        while loc > 0 {
            let port = Int(loc & 0xF)
            if port > 0 {
                path.append(port)
            }
            loc >>= 4
        }
        if path.isEmpty {
            return "Root"
        }
        return path.map { String($0) }.joined(separator: " → ")
    }
}

// MARK: - USB Speed Enum
enum USBSpeed: Int, CaseIterable {
    case unknown = -1
    case low = 0          // 1.5 Mbps
    case full = 1         // 12 Mbps
    case high = 2         // 480 Mbps
    case super_ = 3       // 5 Gbps
    case superPlus = 4    // 10 Gbps
    case superPlusBy2 = 5 // 20 Gbps

    var description: String {
        switch self {
        case .unknown: return "Unknown Speed"
        case .low: return "Low Speed (USB 1.0)"
        case .full: return "Full Speed (USB 1.1)"
        case .high: return "High Speed (USB 2.0)"
        case .super_: return "SuperSpeed (USB 3.0)"
        case .superPlus: return "SuperSpeed+ (USB 3.1/3.2)"
        case .superPlusBy2: return "SuperSpeed+ 2x2 (USB 3.2)"
        }
    }

    var laymanDescription: String {
        switch self {
        case .unknown: return "Speed unknown – may need a better cable or port"
        case .low: return "Very Slow – only good for basic keyboards/mice"
        case .full: return "Slow – outdated USB 1.1, fine for simple devices"
        case .high: return "Medium – standard USB 2.0, good for most devices"
        case .super_: return "Fast – great for flash drives and external storage"
        case .superPlus: return "Very Fast – excellent for SSDs and video capture"
        case .superPlusBy2: return "Blazing Fast – top-tier speed for demanding tasks"
        }
    }

    var shortDescription: String {
        switch self {
        case .unknown: return "Unknown"
        case .low: return "1.5 Mbps"
        case .full: return "12 Mbps"
        case .high: return "480 Mbps"
        case .super_: return "5 Gbps"
        case .superPlus: return "10 Gbps"
        case .superPlusBy2: return "20 Gbps"
        }
    }

    var color: Color {
        switch self {
        case .unknown: return .gray
        case .low: return .red
        case .full: return .orange
        case .high: return .yellow
        case .super_: return .green
        case .superPlus: return .blue
        case .superPlusBy2: return .purple
        }
    }

    var usbVersionString: String {
        switch self {
        case .unknown: return "?"
        case .low, .full: return "1.x"
        case .high: return "2.0"
        case .super_: return "3.0/3.1 Gen 1"
        case .superPlus: return "3.1 Gen 2/3.2 Gen 2"
        case .superPlusBy2: return "3.2 Gen 2x2"
        }
    }

    var maxPowerDelivery: String {
        switch self {
        case .unknown: return "Unknown"
        case .low, .full: return "100 mA (0.5W)"
        case .high: return "500 mA (2.5W)"
        case .super_, .superPlus, .superPlusBy2: return "900 mA (4.5W) / Up to 3A with USB-C PD"
        }
    }

    var icon: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .low: return "tortoise"
        case .full: return "hare"
        case .high: return "bolt"
        case .super_: return "bolt.fill"
        case .superPlus: return "bolt.horizontal.fill"
        case .superPlusBy2: return "bolt.horizontal.circle.fill"
        }
    }
}

// MARK: - USB Manager
class USBManager: ObservableObject {
    @Published var devices: [USBDevice] = []
    @Published var controllers: [USBController] = []
    @Published var thunderboltDevices: [ThunderboltDevice] = []
    @Published var lastUpdated: Date = Date()
    @Published var isScanning: Bool = false
    @Published var scanLog: [String] = []

    private var notificationPort: IONotificationPortRef?
    private var addedIterator: io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0

    init() {
        refreshAll()
        setupUSBNotifications()
    }

    deinit {
        if addedIterator != 0 { IOObjectRelease(addedIterator) }
        if removedIterator != 0 { IOObjectRelease(removedIterator) }
        if let port = notificationPort { IONotificationPortDestroy(port) }
    }

    private func log(_ message: String) {
        DispatchQueue.main.async {
            self.scanLog.append("[\(Date().formatted(date: .omitted, time: .standard))] \(message)")
            if self.scanLog.count > 100 { self.scanLog.removeFirst() }
        }
    }

    private func setupUSBNotifications() {
        notificationPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let port = notificationPort else { return }

        let runLoopSource = IONotificationPortGetRunLoopSource(port).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)

        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        IOServiceAddMatchingNotification(port, kIOFirstMatchNotification, matchingDict,
            { (refcon, iterator) in
                while case let device = IOIteratorNext(iterator), device != 0 { IOObjectRelease(device) }
                guard let refcon = refcon else { return }
                DispatchQueue.main.async {
                    Unmanaged<USBManager>.fromOpaque(refcon).takeUnretainedValue().refreshAll()
                }
            }, selfPtr, &addedIterator)

        while case let device = IOIteratorNext(addedIterator), device != 0 { IOObjectRelease(device) }

        let matchingDict2 = IOServiceMatching(kIOUSBDeviceClassName)
        IOServiceAddMatchingNotification(port, kIOTerminatedNotification, matchingDict2,
            { (refcon, iterator) in
                while case let device = IOIteratorNext(iterator), device != 0 { IOObjectRelease(device) }
                guard let refcon = refcon else { return }
                DispatchQueue.main.async {
                    Unmanaged<USBManager>.fromOpaque(refcon).takeUnretainedValue().refreshAll()
                }
            }, selfPtr, &removedIterator)

        while case let device = IOIteratorNext(removedIterator), device != 0 { IOObjectRelease(device) }
    }

    func refreshAll() {
        isScanning = true
        log("Starting full scan...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let devices = self?.scanUSBDevices() ?? []
            let controllers = self?.scanUSBControllers() ?? []
            let thunderbolt = self?.scanThunderboltDevices() ?? []

            DispatchQueue.main.async {
                self?.devices = devices
                self?.controllers = controllers
                self?.thunderboltDevices = thunderbolt
                self?.lastUpdated = Date()
                self?.isScanning = false
                self?.log("Scan complete: \(devices.count) USB devices, \(controllers.count) controllers, \(thunderbolt.count) Thunderbolt devices")
            }
        }
    }

    // MARK: - Scan USB Controllers
    private func scanUSBControllers() -> [USBController] {
        var controllers: [USBController] = []

        let controllerClasses = ["AppleUSBXHCI", "AppleUSBEHCI", "AppleUSBOHCI", "AppleUSBUHCI", "IOUSBController", "AppleUSB20XHCIPort", "IOUSBHostController"]

        for className in controllerClasses {
            let matchingDict = IOServiceMatching(className)
            var iterator: io_iterator_t = 0

            if IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == KERN_SUCCESS {
                defer { IOObjectRelease(iterator) }

                while case let service = IOIteratorNext(iterator), service != 0 {
                    defer { IOObjectRelease(service) }

                    if let controller = createController(from: service, className: className) {
                        controllers.append(controller)
                    }
                }
            }
        }

        return controllers
    }

    private func createController(from service: io_service_t, className: String) -> USBController? {
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = properties?.takeRetainedValue() as? [String: Any] else { return nil }

        var nameBuffer = [CChar](repeating: 0, count: 256)
        var name = className
        if IORegistryEntryGetName(service, &nameBuffer) == KERN_SUCCESS {
            name = String(cString: nameBuffer)
        }

        let busPower = props["Bus Power Available"] as? Int ?? props["AAPL,current-available"] as? Int ?? 0
        let locationID = (props["locationID"] as? NSNumber)?.uint32Value ?? 0
        let isBuiltIn = props["Built-In"] as? Bool ?? (props["built-in"] != nil)

        var controllerType = "Unknown"
        if className.contains("XHCI") { controllerType = "xHCI (USB 3.0+)" }
        else if className.contains("EHCI") { controllerType = "EHCI (USB 2.0)" }
        else if className.contains("OHCI") || className.contains("UHCI") { controllerType = "OHCI/UHCI (USB 1.x)" }

        let rawProps = props.compactMapValues { value -> String? in
            if let str = value as? String { return str }
            if let num = value as? NSNumber { return num.stringValue }
            if let data = value as? Data { return data.map { String(format: "%02X", $0) }.joined(separator: " ") }
            return nil
        }

        return USBController(
            name: name,
            className: className,
            locationID: locationID,
            busPowerAvailable: busPower,
            isBuiltIn: isBuiltIn,
            controllerType: controllerType,
            pciInfo: props["pcidebug"] as? String ?? "",
            supportsUSB3: className.contains("XHCI") || name.contains("3.0"),
            rawProperties: rawProps
        )
    }

    // MARK: - Scan Thunderbolt
    private func scanThunderboltDevices() -> [ThunderboltDevice] {
        var devices: [ThunderboltDevice] = []

        let matchingDict = IOServiceMatching("IOThunderboltPort")
        var iterator: io_iterator_t = 0

        if IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator) }

            while case let service = IOIteratorNext(iterator), service != 0 {
                defer { IOObjectRelease(service) }

                if let tbDevice = createThunderboltDevice(from: service) {
                    devices.append(tbDevice)
                }
            }
        }

        let matchingDict2 = IOServiceMatching("IOThunderboltSwitch")
        var iterator2: io_iterator_t = 0

        if IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict2, &iterator2) == KERN_SUCCESS {
            defer { IOObjectRelease(iterator2) }

            while case let service = IOIteratorNext(iterator2), service != 0 {
                defer { IOObjectRelease(service) }

                if let tbDevice = createThunderboltDevice(from: service) {
                    devices.append(tbDevice)
                }
            }
        }

        return devices
    }

    private func createThunderboltDevice(from service: io_service_t) -> ThunderboltDevice? {
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = properties?.takeRetainedValue() as? [String: Any] else { return nil }

        var nameBuffer = [CChar](repeating: 0, count: 256)
        var name = "Thunderbolt Device"
        if IORegistryEntryGetName(service, &nameBuffer) == KERN_SUCCESS {
            name = String(cString: nameBuffer)
        }

        let uid = props["UID"] as? String ?? props["Thunderbolt Device UID"] as? String ?? ""
        let vendorName = props["Device Vendor Name"] as? String ?? props["Vendor Name"] as? String ?? ""
        let deviceName = props["Device Model Name"] as? String ?? props["Device Name"] as? String ?? name

        var generation = 3
        if let gen = props["Thunderbolt Generation"] as? Int { generation = gen }
        else if name.contains("Thunderbolt 4") || vendorName.contains("Thunderbolt 4") { generation = 4 }
        else if name.contains("Thunderbolt 3") { generation = 3 }
        else if name.contains("Thunderbolt 2") { generation = 2 }
        else if name.contains("Thunderbolt 1") || name.contains("Light Peak") { generation = 1 }

        let rawProps = props.compactMapValues { value -> String? in
            if let str = value as? String { return str }
            if let num = value as? NSNumber { return num.stringValue }
            if let data = value as? Data, data.count < 100 { return data.map { String(format: "%02X", $0) }.joined(separator: " ") }
            return nil
        }

        return ThunderboltDevice(
            name: name,
            vendorName: vendorName,
            deviceName: deviceName,
            uid: uid,
            routeString: props["Route String"] as? String ?? "",
            linkSpeed: props["Link Speed"] as? Int ?? 0,
            linkWidth: props["Link Width"] as? Int ?? 0,
            generation: generation,
            isConnected: props["Power State"] as? Int ?? 1 > 0,
            rawProperties: rawProps
        )
    }

    // MARK: - Scan USB Devices
    private func scanUSBDevices() -> [USBDevice] {
        var devices: [USBDevice] = []

        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName)
        var iterator: io_iterator_t = 0

        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator) == KERN_SUCCESS else { return devices }
        defer { IOObjectRelease(iterator) }

        while case let usbDevice = IOIteratorNext(iterator), usbDevice != 0 {
            defer { IOObjectRelease(usbDevice) }
            if let device = createUSBDevice(from: usbDevice) {
                devices.append(device)
            }
        }

        return devices.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func createUSBDevice(from service: io_service_t) -> USBDevice? {
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = properties?.takeRetainedValue() as? [String: Any] else { return nil }

        let vendorID = props[kUSBVendorID] as? Int ?? 0
        let productID = props[kUSBProductID] as? Int ?? 0
        let vendorName = props[kUSBVendorString] as? String ?? props["USB Vendor Name"] as? String ?? ""
        let productName = props[kUSBProductString] as? String ?? props["USB Product Name"] as? String ?? ""
        let serialNumber = props[kUSBSerialNumberString] as? String ?? ""
        let speedRaw = props[kUSBDeviceSpeed] as? Int ?? props["speed"] as? Int ?? -1
        let deviceClass = props[kUSBDeviceClass] as? Int ?? 0
        let deviceSubClass = props[kUSBDeviceSubClass] as? Int ?? 0
        let deviceProtocol = props[kUSBDeviceProtocol] as? Int ?? 0
        let maxPower = props["Device Current"] as? Int ?? props[kUSBMaxPower] as? Int ?? props["bMaxPower"] as? Int ?? 0
        let bcdUSB = props["bcdUSB"] as? Int ?? 0
        let bcdDevice = props["bcdDevice"] as? Int ?? 0
        let locationID = (props[kUSBDevicePropertyLocationID] as? NSNumber)?.uint32Value ?? 0

        // Extended properties
        let currentAvailable = props["AAPL,current-available"] as? Int ?? props["Current Available"] as? Int ?? 0
        let extraCurrent = props["AAPL,current-extra-in-sleep"] as? Int ?? 0
        let busPower = props["Bus Power Available"] as? Int ?? 0
        let isCaptive = props["non-removable"] as? Bool ?? props["Captive"] as? Bool ?? false
        let isInternal = props["internal"] as? Bool ?? props["Built-In"] as? Bool ?? false
        let sleepCurrent = props["Sleep Current"] as? Int ?? props["AAPL,sleep-current"] as? Int ?? 0
        let sessionID = (props["sessionID"] as? NSNumber)?.uint64Value ?? 0
        let portType = props["port-type"] as? String ?? props["Port Type"] as? String ?? "Standard"

        // Determine device name
        var name = productName.isEmpty ? vendorName : productName
        if name.isEmpty {
            var nameBuffer = [CChar](repeating: 0, count: 256)
            if IORegistryEntryGetName(service, &nameBuffer) == KERN_SUCCESS {
                name = String(cString: nameBuffer)
            }
        }
        if name.isEmpty || name == "IOUSBHostDevice" {
            name = "USB Device (\(String(format: "%04X:%04X", vendorID, productID)))"
        }

        // USB version
        let usbVersion: String
        if bcdUSB > 0 {
            let major = (bcdUSB >> 8) & 0xFF
            let minor = (bcdUSB >> 4) & 0x0F
            let patch = bcdUSB & 0x0F
            usbVersion = "\(major).\(minor)\(patch > 0 ? ".\(patch)" : "")"
        } else {
            usbVersion = USBSpeed(rawValue: speedRaw)?.usbVersionString ?? "Unknown"
        }

        // Try to determine parent controller
        var parentName = ""
        var parent: io_registry_entry_t = 0
        if IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS {
            defer { IOObjectRelease(parent) }
            var parentNameBuffer = [CChar](repeating: 0, count: 256)
            if IORegistryEntryGetName(parent, &parentNameBuffer) == KERN_SUCCESS {
                parentName = String(cString: parentNameBuffer)
            }
        }

        // Raw properties for debugging/advanced view
        let rawProps = props.compactMapValues { value -> String? in
            if let str = value as? String { return str }
            if let num = value as? NSNumber { return num.stringValue }
            if let data = value as? Data, data.count < 100 {
                return data.map { String(format: "%02X", $0) }.joined(separator: " ")
            }
            if let arr = value as? [Any] {
                return arr.map { "\($0)" }.joined(separator: ", ")
            }
            return String(describing: value)
        }

        let isHub = deviceClass == 9
        let portCount = props["Ports"] as? Int ?? props["PortCount"] as? Int ?? 0

        return USBDevice(
            name: name,
            vendorID: vendorID,
            productID: productID,
            vendorName: vendorName,
            productName: productName,
            serialNumber: serialNumber,
            speed: USBSpeed(rawValue: speedRaw) ?? .unknown,
            deviceClass: deviceClass,
            deviceSubClass: deviceSubClass,
            deviceProtocol: deviceProtocol,
            maxPower: maxPower,
            usbVersion: usbVersion,
            locationID: locationID,
            isHub: isHub,
            portCount: portCount,
            bcdDevice: bcdDevice,
            currentAvailable: currentAvailable,
            extraCurrentInSleep: extraCurrent,
            busPowerAvailable: busPower,
            isCaptive: isCaptive,
            isInternal: isInternal,
            sleepCurrent: sleepCurrent,
            sessionID: sessionID,
            portType: portType,
            parentControllerName: parentName,
            rawProperties: rawProps
        )
    }
}

// MARK: - View Mode
enum ViewMode: String, CaseIterable {
    case devices = "Devices"
    case controllers = "Controllers"
    case thunderbolt = "Thunderbolt"
    case rawData = "Raw Data"

    var icon: String {
        switch self {
        case .devices: return "cable.connector"
        case .controllers: return "cpu"
        case .thunderbolt: return "bolt.horizontal"
        case .rawData: return "list.bullet.rectangle"
        }
    }
}

// MARK: - Content View
struct ContentView: View {
    @StateObject private var usbManager = USBManager()
    @State private var selectedDevice: USBDevice?
    @State private var selectedController: USBController?
    @State private var selectedThunderbolt: ThunderboltDevice?
    @State private var searchText = ""
    @State private var viewMode: ViewMode = .devices
    @State private var showRawProperties = false

    var filteredDevices: [USBDevice] {
        if searchText.isEmpty { return usbManager.devices }
        return usbManager.devices.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.vendorName.localizedCaseInsensitiveContains(searchText) ||
            $0.productName.localizedCaseInsensitiveContains(searchText) ||
            $0.vendorIDHex.localizedCaseInsensitiveContains(searchText) ||
            $0.productIDHex.localizedCaseInsensitiveContains(searchText) ||
            $0.serialNumber.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Mode Picker
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                // Stats Header
                HStack(spacing: 16) {
                    StatBadge(label: "USB", count: usbManager.devices.count, color: .blue)
                    StatBadge(label: "Controllers", count: usbManager.controllers.count, color: .green)
                    StatBadge(label: "TB", count: usbManager.thunderboltDevices.count, color: .purple)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // Content based on mode
                Group {
                    switch viewMode {
                    case .devices:
                        deviceListView
                    case .controllers:
                        controllerListView
                    case .thunderbolt:
                        thunderboltListView
                    case .rawData:
                        rawDataListView
                    }
                }

                Divider()

                // Footer
                footerView
            }
            .frame(minWidth: 320)
        } detail: {
            detailView
        }
        .searchable(text: $searchText, prompt: "Search...")
        .navigationTitle("USB Inspector Pro")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showRawProperties.toggle() }) {
                    Image(systemName: showRawProperties ? "doc.text.fill" : "doc.text")
                }
                .help("Toggle raw properties")
            }
            ToolbarItem(placement: .automatic) {
                Button(action: { usbManager.refreshAll() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
    }

    // MARK: - Device List
    var deviceListView: some View {
        List(filteredDevices, selection: $selectedDevice) { device in
            DeviceRow(device: device)
                .tag(device)
        }
        .listStyle(.inset)
    }

    // MARK: - Controller List
    var controllerListView: some View {
        List(usbManager.controllers, selection: $selectedController) { controller in
            ControllerRow(controller: controller)
                .tag(controller)
        }
        .listStyle(.inset)
    }

    // MARK: - Thunderbolt List
    var thunderboltListView: some View {
        Group {
            if usbManager.thunderboltDevices.isEmpty {
                ContentUnavailableView {
                    Label("No Thunderbolt Devices", systemImage: "bolt.horizontal.circle")
                } description: {
                    Text("No Thunderbolt ports or devices detected. Thunderbolt ports look like USB-C but have a ⚡ lightning bolt symbol next to them.")
                }
            } else {
                List(usbManager.thunderboltDevices, selection: $selectedThunderbolt) { device in
                    ThunderboltRow(device: device)
                        .tag(device)
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Raw Data List
    var rawDataListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Scan Log")
                    .font(.headline)
                    .padding(.horizontal)

                ForEach(usbManager.scanLog.reversed(), id: \.self) { log in
                    Text(log)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    // MARK: - Footer
    var footerView: some View {
        HStack {
            if usbManager.isScanning {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Scanning...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Updated: \(usbManager.lastUpdated.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Detail View
    @ViewBuilder
    var detailView: some View {
        switch viewMode {
        case .devices:
            if let device = selectedDevice {
                DeviceDetailView(device: device, showRaw: showRawProperties)
            } else {
                ContentUnavailableView {
                    Label("Select a Device", systemImage: "cable.connector")
                } description: {
                    Text("Click on any USB device in the list to see detailed information about its speed, power usage, and capabilities.")
                }
            }
        case .controllers:
            if let controller = selectedController {
                ControllerDetailView(controller: controller, showRaw: showRawProperties)
            } else {
                ContentUnavailableView {
                    Label("Select a Controller", systemImage: "cpu")
                } description: {
                    Text("USB Controllers are the chips that manage your USB ports. Select one to see what speeds it supports.")
                }
            }
        case .thunderbolt:
            if let device = selectedThunderbolt {
                ThunderboltDetailView(device: device, showRaw: showRawProperties)
            } else {
                ContentUnavailableView {
                    Label("Select a Thunderbolt Device", systemImage: "bolt.horizontal")
                } description: {
                    Text("Thunderbolt is faster than USB. Select a device to see its capabilities.")
                }
            }
        case .rawData:
            RawDataOverview(manager: usbManager)
        }
    }
}

// MARK: - Stat Badge
struct StatBadge: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .fontWeight(.bold)
            Text(label)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.2))
        .cornerRadius(6)
    }
}

// MARK: - Device Row
struct DeviceRow: View {
    let device: USBDevice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.classInfo.icon)
                .font(.title2)
                .foregroundColor(device.speed.color)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(device.speed.shortDescription)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(device.speed.color.opacity(0.2))
                        .cornerRadius(4)

                    Text(device.classInfo.name)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if device.isInternal {
                        Image(systemName: "internaldrive")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Quality indicator
            Circle()
                .fill(device.connectionQuality.color)
                .frame(width: 8, height: 8)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Controller Row
struct ControllerRow: View {
    let controller: USBController

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.title2)
                .foregroundColor(controller.supportsUSB3 ? .green : .yellow)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(controller.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(controller.controllerType)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(controller.supportsUSB3 ? Color.green.opacity(0.2) : Color.yellow.opacity(0.2))
                        .cornerRadius(4)

                    if controller.isBuiltIn {
                        Text("Built-in")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Thunderbolt Row
struct ThunderboltRow: View {
    let device: ThunderboltDevice

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.horizontal.fill")
                .font(.title2)
                .foregroundColor(device.color)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(device.generationString)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(device.color.opacity(0.2))
                        .cornerRadius(4)

                    if !device.vendorName.isEmpty {
                        Text(device.vendorName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Device Detail View
struct DeviceDetailView: View {
    let device: USBDevice
    let showRaw: Bool
    @State private var expandedSections: Set<String> = ["speed", "device", "power", "quality"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                deviceHeader

                Divider()

                // Connection Quality Card
                qualityCard

                // Speed Section
                CollapsibleSection(title: "⚡ How Fast Is It?", icon: device.speed.icon, isExpanded: expandedSections.contains("speed")) {
                    SpeedDetailView(device: device)
                }

                // Device Info Section
                CollapsibleSection(title: "📋 Device Details", icon: "info.circle", isExpanded: expandedSections.contains("device")) {
                    deviceInfoSection
                }

                // Technical Details
                CollapsibleSection(title: "🔧 Developer Info", icon: "gearshape.2", isExpanded: expandedSections.contains("technical")) {
                    technicalSection
                }

                // Power Section
                CollapsibleSection(title: "🔋 Power Usage", icon: "bolt.fill", isExpanded: expandedSections.contains("power")) {
                    powerSection
                }

                // Topology Section
                CollapsibleSection(title: "🔌 Connection Path", icon: "point.3.connected.trianglepath.dotted", isExpanded: expandedSections.contains("topology")) {
                    topologySection
                }

                // Raw Properties
                if showRaw {
                    CollapsibleSection(title: "📄 Raw System Data", icon: "doc.text", isExpanded: expandedSections.contains("raw")) {
                        rawPropertiesSection
                    }
                }

                Spacer(minLength: 50)
            }
            .padding(24)
        }
        .frame(minWidth: 450)
    }

    var deviceHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(device.speed.color.opacity(0.2))
                    .frame(width: 70, height: 70)
                Image(systemName: device.classInfo.icon)
                    .font(.system(size: 32))
                    .foregroundColor(device.speed.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 8) {
                    if !device.vendorName.isEmpty {
                        Text(device.vendorName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(device.classInfo.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Layman-friendly explanation
                Text(device.classInfo.layman)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }

            Spacer()
        }
    }

    var qualityCard: some View {
        let quality = device.connectionQuality
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(quality.color)
                    .frame(width: 12, height: 12)
                Text("Connection Quality: \(quality.rating)")
                    .font(.headline)
                Spacer()
                Text("\(quality.score)/100")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(quality.color.opacity(0.2))
                    .cornerRadius(6)
            }

            // Summary explanation
            Text(quality.summary)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()

            // Detailed findings
            ForEach(quality.issues, id: \.self) { issue in
                Text(issue)
                    .font(.callout)
                    .foregroundColor(quality.score >= 80 ? .primary : .secondary)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }

    var deviceInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // What is this device?
            if !device.productName.isEmpty || !device.vendorName.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("📦 What is this?")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(device.productName.isEmpty ? device.vendorName : device.productName)
                        .font(.callout)
                    if !device.vendorName.isEmpty && !device.productName.isEmpty {
                        Text("Made by \(device.vendorName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Divider()
            }

            DetailRowWithHelp(label: "Serial Number", value: device.serialNumber.isEmpty ? "None" : device.serialNumber, help: "A unique ID for this specific device – useful for tracking or warranty")
            DetailRowWithHelp(label: "Device Version", value: device.bcdDeviceString, help: "The hardware/firmware version of this device")
            DetailRowWithHelp(label: "USB Version", value: device.usbVersion, help: "Which USB standard this device was built for")
            if device.isHub {
                DetailRowWithHelp(label: "Available Ports", value: "\(device.portCount) ports", help: "How many devices you can plug into this hub")
            }
        }
    }

    var technicalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("🔧 For Developers & Troubleshooting")
                .font(.caption)
                .foregroundColor(.secondary)

            DetailRow(label: "Vendor ID", value: device.vendorIDHex)
            DetailRow(label: "Product ID", value: device.productIDHex)
            DetailRow(label: "Device Class", value: "\(device.deviceClass) (\(device.classInfo.name))")
            DetailRow(label: "SubClass", value: "\(device.deviceSubClass)")
            DetailRow(label: "Protocol", value: "\(device.deviceProtocol)")
            DetailRow(label: "Port Type", value: device.portType)
            if device.sessionID > 0 {
                DetailRow(label: "Session ID", value: String(format: "0x%016llX", device.sessionID))
            }
        }
    }

    var powerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Power explanation
            Text("⚡ How much power does this device use?")
                .font(.subheadline)
                .fontWeight(.medium)

            // Visual power meter
            if device.maxPower > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Power Usage")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if device.busPowerAvailable > 0 {
                            Text(device.maxPower > device.busPowerAvailable ? "⚠️ Needs more power!" : "✅ OK")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }

                    if device.busPowerAvailable > 0 {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.gray.opacity(0.2))
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(device.maxPower > device.busPowerAvailable ? Color.red : Color.green)
                                    .frame(width: geo.size.width * min(CGFloat(device.maxPower) / CGFloat(device.busPowerAvailable), 1.0))
                            }
                        }
                        .frame(height: 10)
                    }

                    // Plain English power info
                    let watts = Double(device.maxPower) * 5.0 / 1000.0
                    let wattsString = String(format: "%.1f", watts)
                    Text("Uses \(device.maxPower) mA (\(wattsString) watts)")
                        .font(.callout)

                    if device.busPowerAvailable > 0 {
                        Text("Port provides up to \(device.busPowerAvailable) mA")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()
            }

            // What this means
            VStack(alignment: .leading, spacing: 4) {
                if device.maxPower > 500 {
                    Label("High-power device – may need a powered hub or direct connection", systemImage: "bolt.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if device.maxPower > 100 {
                    Label("Normal power usage – works with any USB port", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if device.maxPower > 0 {
                    Label("Low power device – very efficient!", systemImage: "leaf.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            if device.sleepCurrent > 0 || device.extraCurrentInSleep > 0 {
                Divider()
                Text("💤 While computer sleeps:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if device.sleepCurrent > 0 {
                    Text("Uses \\(device.sleepCurrent) mA to stay ready")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    var topologySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🔌 Where is this device connected?")
                .font(.subheadline)
                .fontWeight(.medium)

            // Plain English connection path
            VStack(alignment: .leading, spacing: 6) {
                if !device.parentControllerName.isEmpty {
                    Label("Connected through \\(device.parentControllerName)", systemImage: "arrow.turn.down.right")
                        .font(.callout)
                }

                HStack(spacing: 16) {
                    if device.isInternal {
                        Label("Built-in", systemImage: "internaldrive")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    if device.isCaptive {
                        Label("Permanently attached", systemImage: "cable.connector")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                    if !device.isInternal && !device.isCaptive {
                        Label("External / Removable", systemImage: "eject")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }

            Divider()

            // Technical details (collapsed)
            DisclosureGroup("Technical Details") {
                VStack(spacing: 6) {
                    DetailRow(label: "Location ID", value: String(format: "0x%08X", device.locationID))
                    DetailRow(label: "Port Path", value: device.locationDescription)
                }
                .padding(.top, 4)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    var rawPropertiesSection: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(device.rawProperties.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack(alignment: .top) {
                    Text(key)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 200, alignment: .leading)
                    Text(value)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }
}

// MARK: - Speed Detail View
struct SpeedDetailView: View {
    let device: USBDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Main speed display
            HStack {
                Image(systemName: device.speed.icon)
                    .font(.title)
                    .foregroundColor(device.speed.color)

                VStack(alignment: .leading) {
                    Text(device.speed.laymanDescription)
                        .font(.headline)
                    Text(device.speed.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(device.speed.shortDescription)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(device.speed.color)
            }

            // Real-world explanation
            Text(device.theoreticalBandwidth.realWorld)
                .font(.callout)
                .foregroundColor(.secondary)
                .italic()
                .padding(.vertical, 4)

            Divider()

            // Speed bar with labels
            VStack(alignment: .leading, spacing: 4) {
                Text("How fast is this compared to other USB?")
                    .font(.caption)
                    .foregroundColor(.secondary)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.2))
                        RoundedRectangle(cornerRadius: 6)
                            .fill(LinearGradient(colors: [device.speed.color.opacity(0.7), device.speed.color], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * speedPercentage)
                    }
                }
                .frame(height: 12)

                HStack {
                    Text("🐢 Slowest")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("🚀 Fastest")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Plain English speed info
            VStack(alignment: .leading, spacing: 6) {
                DetailRowWithHelp(
                    label: "Max Speed",
                    value: device.theoreticalBandwidth.speed,
                    help: "The fastest this connection can theoretically go"
                )
                DetailRowWithHelp(
                    label: "Real-World Speed",
                    value: device.theoreticalBandwidth.practical,
                    help: "What you'll actually see when copying files"
                )
                DetailRowWithHelp(
                    label: "Power Delivery",
                    value: device.speed.maxPowerDelivery,
                    help: "How much power this USB version can provide for charging"
                )
            }
        }
    }

    var speedPercentage: CGFloat {
        // Scale to USB4/TB4 40 Gbps max
        switch device.speed {
        case .unknown: return 0.02
        case .low: return 0.02        // 1.5 Mbps
        case .full: return 0.03       // 12 Mbps
        case .high: return 0.12       // 480 Mbps
        case .super_: return 0.125    // 5 Gbps
        case .superPlus: return 0.25  // 10 Gbps
        case .superPlusBy2: return 0.5 // 20 Gbps
        }
    }
}

// MARK: - Controller Detail View
struct ControllerDetailView: View {
    let controller: USBController
    let showRaw: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(controller.supportsUSB3 ? Color.green.opacity(0.2) : Color.yellow.opacity(0.2))
                            .frame(width: 70, height: 70)
                        Image(systemName: "cpu")
                            .font(.system(size: 32))
                            .foregroundColor(controller.supportsUSB3 ? .green : .yellow)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(controller.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(controller.controllerType)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        // Layman explanation
                        Text(controller.supportsUSB3 ? "This controller supports fast USB 3.0+ speeds" : "Older controller – supports USB 2.0 speeds only")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }

                    Spacer()
                }

                Divider()

                // What does this mean?
                VStack(alignment: .leading, spacing: 8) {
                    Text("💡 What is a USB Controller?")
                        .font(.headline)
                    Text("A USB controller is a chip inside your Mac that manages USB ports. Each controller can handle multiple ports, and the type of controller determines the maximum speed your devices can achieve.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(10)

                DetailSection(title: "📋 Controller Details") {
                    DetailRow(label: "Type", value: controller.controllerType)
                    DetailRow(label: "Location", value: controller.isBuiltIn ? "Built into your Mac" : "External (add-on card or hub)")
                    DetailRow(label: "Speed Support", value: controller.supportsUSB3 ? "✅ USB 3.0+ (up to 10+ Gbps)" : "⚠️ USB 2.0 only (max 480 Mbps)")
                }

                DetailSection(title: "⚡ Power Available") {
                    Text(controller.powerDescription)
                        .font(.callout)
                    Text("This is how much power devices connected to this controller can draw.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !controller.pciInfo.isEmpty {
                    DetailSection(title: "🔧 Technical: PCI Information") {
                        Text(controller.pciInfo)
                            .font(.system(.caption, design: .monospaced))
                    }
                }

                if showRaw && !controller.rawProperties.isEmpty {
                    DetailSection(title: "📄 Raw System Data") {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(controller.rawProperties.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                HStack(alignment: .top) {
                                    Text(key)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 200, alignment: .leading)
                                    Text(value)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: 50)
            }
            .padding(24)
        }
        .frame(minWidth: 450)
    }
}

// MARK: - Thunderbolt Detail View
struct ThunderboltDetailView: View {
    let device: ThunderboltDevice
    let showRaw: Bool

    var speedExplanation: String {
        switch device.generation {
        case 4: return "Thunderbolt 4 is the latest – up to 40 Gbps, supports daisy-chaining, external GPUs, and multiple 4K displays."
        case 3: return "Thunderbolt 3 offers up to 40 Gbps – great for external drives, docks, and displays."
        case 2: return "Thunderbolt 2 offers up to 20 Gbps – still capable for external drives and displays."
        case 1: return "Original Thunderbolt offers up to 10 Gbps – faster than USB 3.0."
        default: return "Thunderbolt is much faster than USB – perfect for demanding tasks like video editing."
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(device.color.opacity(0.2))
                            .frame(width: 70, height: 70)
                        Image(systemName: "bolt.horizontal.fill")
                            .font(.system(size: 32))
                            .foregroundColor(device.color)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(device.generationString)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(speedExplanation)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }

                    Spacer()

                    Text(device.speedDescription)
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(device.color.opacity(0.2))
                        .cornerRadius(8)
                }

                Divider()

                // What is Thunderbolt?
                VStack(alignment: .leading, spacing: 8) {
                    Text("⚡ What is Thunderbolt?")
                        .font(.headline)
                    Text("Thunderbolt is a high-speed connection technology developed by Intel and Apple. It's much faster than USB and can carry data, video, and power all through one cable. Thunderbolt 3 and 4 use the same connector as USB-C.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.purple.opacity(0.1))
                .cornerRadius(10)

                DetailSection(title: "📦 Device Info") {
                    if !device.vendorName.isEmpty {
                        DetailRow(label: "Made by", value: device.vendorName)
                    }
                    if !device.deviceName.isEmpty && device.deviceName != device.name {
                        DetailRow(label: "Model", value: device.deviceName)
                    }
                    DetailRow(label: "Status", value: device.isConnected ? "✅ Connected and working" : "⚠️ Disconnected")
                }

                DetailSection(title: "⚡ Speed & Performance") {
                    DetailRow(label: "Generation", value: device.generationString)
                    DetailRow(label: "Maximum Speed", value: device.speedDescription)
                    if device.linkSpeed > 0 {
                        DetailRow(label: "Current Link Speed", value: "\(device.linkSpeed) Gbps")
                    }
                    if device.linkWidth > 0 {
                        DetailRow(label: "Lane Width", value: "\(device.linkWidth)x lanes")
                        Text("More lanes = more bandwidth. Thunderbolt uses multiple lanes for higher throughput.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }

                if showRaw && !device.rawProperties.isEmpty {
                    DetailSection(title: "📄 Raw System Data") {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(device.rawProperties.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                HStack(alignment: .top) {
                                    Text(key)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 200, alignment: .leading)
                                    Text(value)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: 50)
            }
            .padding(24)
        }
        .frame(minWidth: 450)
    }
}

// MARK: - Raw Data Overview
struct RawDataOverview: View {
    @ObservedObject var manager: USBManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("System USB/Thunderbolt Overview")
                    .font(.title2)
                    .fontWeight(.bold)

                Divider()

                DetailSection(title: "Summary") {
                    DetailRow(label: "Total USB Devices", value: "\(manager.devices.count)")
                    DetailRow(label: "USB Controllers", value: "\(manager.controllers.count)")
                    DetailRow(label: "Thunderbolt Devices", value: "\(manager.thunderboltDevices.count)")
                    DetailRow(label: "USB Hubs", value: "\(manager.devices.filter { $0.isHub }.count)")
                    DetailRow(label: "Internal Devices", value: "\(manager.devices.filter { $0.isInternal }.count)")
                }

                DetailSection(title: "Speed Distribution") {
                    ForEach(USBSpeed.allCases.filter { $0 != .unknown }, id: \.self) { speed in
                        let count = manager.devices.filter { $0.speed == speed }.count
                        if count > 0 {
                            HStack {
                                Circle()
                                    .fill(speed.color)
                                    .frame(width: 10, height: 10)
                                Text(speed.description)
                                Spacer()
                                Text("\(count)")
                                    .fontWeight(.medium)
                            }
                        }
                    }
                }

                DetailSection(title: "Device Classes") {
                    let classGroups = Dictionary(grouping: manager.devices) { $0.deviceClass }
                    ForEach(classGroups.keys.sorted(), id: \.self) { classID in
                        let devices = classGroups[classID] ?? []
                        let info = usbClassDescriptions[classID] ?? ("Class \(classID)", "", "questionmark.circle", "Unknown device type")
                        HStack {
                            Image(systemName: info.icon)
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                            Text(info.name)
                            Spacer()
                            Text("\(devices.count)")
                                .fontWeight(.medium)
                        }
                    }
                }

                DetailSection(title: "Scan Log") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(manager.scanLog.suffix(20).reversed(), id: \.self) { log in
                            Text(log)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer(minLength: 50)
            }
            .padding(24)
        }
    }
}

// MARK: - Collapsible Section
struct CollapsibleSection<Content: View>: View {
    let title: String
    let icon: String
    @State var isExpanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.accentColor)
                        .frame(width: 20)
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(isExpanded ? 12 : 12, corners: isExpanded ? [.topLeft, .topRight] : .allCorners)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    content
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(12, corners: [.bottomLeft, .bottomRight])
            }
        }
    }
}

// MARK: - Detail Section
struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                content
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
        }
    }
}

// MARK: - Detail Row
struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Detail Row with Help Text
struct DetailRowWithHelp: View {
    let label: String
    let value: String
    let help: String
    @State private var showHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .foregroundColor(.secondary)
                Button(action: { showHelp.toggle() }) {
                    Image(systemName: "questionmark.circle")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(value)
                    .fontWeight(.medium)
                    .textSelection(.enabled)
            }
            if showHelp {
                Text(help)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.leading, 4)
            }
        }
    }
}

// MARK: - Corner Radius Extension
extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomLeft = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
    static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: RectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let tl = corners.contains(.topLeft) ? radius : 0
        let tr = corners.contains(.topRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)

        return path
    }
}

#Preview {
    ContentView()
}
