import Foundation

struct SystemProfile: Sendable, Equatable {
    let userDisplayName: String
    let computerName: String
    let hardwareModel: String
    let processor: String
    let memoryBytes: UInt64
    let operatingSystem: String
    let totalDiskBytes: Int64
    let availableDiskBytes: Int64
    let localeIdentifier: String
    let timeZoneIdentifier: String

    var promptContext: String {
        """
        Local Mac context, supplied by the user’s device: user display name: \(userDisplayName); computer: \(computerName) (\(hardwareModel)); processor: \(processor); memory: \(byteCount(memoryBytes)); operating system: \(operatingSystem); storage: \(byteCount(totalDiskBytes)) total, \(byteCount(availableDiskBytes)) available; locale: \(localeIdentifier); time zone: \(timeZoneIdentifier).
        """
    }

    private func byteCount(_ value: some BinaryInteger) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .decimal)
    }
}

protocol SystemProfileProviding: Sendable {
    func currentProfile() -> SystemProfile
}
