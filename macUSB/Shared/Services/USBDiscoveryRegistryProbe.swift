import Foundation
import IOKit
import IOKit.storage

/// Independent, current evidence for physical USB and SD media. A BSD name
/// or a previous UI snapshot alone is never enough to classify a candidate.
enum USBDiscoveryRegistryProbe {
    struct Media {
        let identity: UInt64
        let removable: Bool?
        let mediaKind: USBTargetMediaKind?
        let busProtocol: String?
        let capacityBytes: Int64?
        let typeEvidence: String
    }

    static func media(named bsd: String, whole: Bool = true) -> Media? {
        var iterator: io_iterator_t = 0
        guard let match = IOServiceMatching("IOMedia"),
              IOServiceGetMatchingServices(0, match, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != IO_OBJECT_NULL {
            defer { IOObjectRelease(service) }
            guard property(service, kIOBSDNameKey as String) as? String == bsd,
                  property(service, kIOMediaWholeKey as String) as? Bool == whole else { continue }
            var identity: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &identity) == KERN_SUCCESS else { return nil }
            let storage: (transport: [String: Any], icon: [String: Any], device: [String: Any])? = USBRegistryTraversal.firstValue(
                from: service,
                retain: { IOObjectRetain($0) == KERN_SUCCESS },
                release: { _ = IOObjectRelease($0) },
                parent: { entry in
                    var parent: io_registry_entry_t = IO_OBJECT_NULL
                    guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS,
                          parent != IO_OBJECT_NULL else { return nil }
                    return parent
                },
                value: { entry in
                    // Stop at the nearest storage device: do not classify a
                    // virtual child by walking past it to its backing USB disk.
                    guard IOObjectConformsTo(entry, "IOBlockStorageDevice") != 0 else { return nil }
                    return (
                        property(entry, "Protocol Characteristics") as? [String: Any] ?? [:],
                        property(entry, "IOMediaIcon") as? [String: Any] ?? [:],
                        property(entry, kIOPropertyDeviceCharacteristicsKey as String) as? [String: Any] ?? [:]
                    )
                }
            )
            let bus = storage?.transport["Physical Interconnect"] as? String
            let location = storage?.transport["Physical Interconnect Location"] as? String
            let mediaIcon = property(service, "IOMediaIcon") as? [String: Any]
            let isSDIcon = mediaIcon?["IOBundleResourceFile"] as? String == "SD.icns"
                || storage?.icon["IOBundleResourceFile"] as? String == "SD.icns"
            // Intel built-in readers report USB/Internal and need not expose
            // SD.icns on these nodes. Match their hardware inquiry fields,
            // never a user-controlled volume label or diskutil MediaName.
            let vendor = (storage?.device[kIOPropertyVendorNameKey as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let product = (storage?.device[kIOPropertyProductNameKey as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let isAppleSDReader = vendor == "APPLE" && product == "SD CARD READER"
            let mediaKind: USBTargetMediaKind?
            switch USBTargetMediaKind.from(busProtocol: bus) {
            case .sdCard: mediaKind = .sdCard
            case .usb where isSDIcon || isAppleSDReader: mediaKind = .sdCard
            case .usb where location == "External": mediaKind = .usb
            default: mediaKind = nil
            }
            return Media(
                identity: identity,
                removable: property(service, kIOMediaRemovableKey as String) as? Bool,
                mediaKind: mediaKind,
                busProtocol: bus,
                capacityBytes: (property(service, kIOMediaSizeKey as String) as? NSNumber).flatMap {
                    Int64($0.stringValue).flatMap { $0 > 0 ? $0 : nil }
                },
                typeEvidence: "transport=\(bus ?? "unknown"), location=\(location ?? "unknown"), sdIcon=\(isSDIcon), vendor=\(vendor ?? "unknown"), product=\(product ?? "unknown"), appleSDReader=\(isAppleSDReader)"
            )
        }
        return nil
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
