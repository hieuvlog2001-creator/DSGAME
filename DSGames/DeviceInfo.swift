import Foundation
import UIKit

struct DeviceInfo {
    static var iosVersion: String { UIDevice.current.systemVersion }

    static var modelIdentifier: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
    }

    static var modelName: String {
        let id = modelIdentifier
        let names: [String: String] = [
            "iPhone12,1":"iPhone 11", "iPhone12,3":"iPhone 11 Pro", "iPhone12,5":"iPhone 11 Pro Max",
            "iPhone13,1":"iPhone 12 mini", "iPhone13,2":"iPhone 12", "iPhone13,3":"iPhone 12 Pro", "iPhone13,4":"iPhone 12 Pro Max",
            "iPhone14,4":"iPhone 13 mini", "iPhone14,5":"iPhone 13", "iPhone14,2":"iPhone 13 Pro", "iPhone14,3":"iPhone 13 Pro Max",
            "iPhone14,7":"iPhone 14", "iPhone14,8":"iPhone 14 Plus", "iPhone15,2":"iPhone 14 Pro", "iPhone15,3":"iPhone 14 Pro Max",
            "iPhone15,4":"iPhone 15", "iPhone15,5":"iPhone 15 Plus", "iPhone16,1":"iPhone 15 Pro", "iPhone16,2":"iPhone 15 Pro Max",
            "iPhone17,3":"iPhone 16", "iPhone17,4":"iPhone 16 Plus", "iPhone17,1":"iPhone 16 Pro", "iPhone17,2":"iPhone 16 Pro Max", "iPhone17,5":"iPhone 16e",
            "i386":"Simulator", "x86_64":"Simulator", "arm64":"Simulator"
        ]
        return names[id] ?? "iPhone (\(id))"
    }
}


extension DeviceInfo {
    /// iOS không cho ứng dụng bên thứ ba đọc IMEI. IDFV là mã thiết bị do iOS cung cấp cho ứng dụng cùng vendor.
    static var vendorIdentifier: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "Không khả dụng"
    }

    static var imeiDisplay: String {
        "Không khả dụng trên iOS"
    }
}
