//
// Copyright (C) 2026 NeterOster <neteroster@gmail.com>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation

private func writeChargeStandardError(_ text: String) {
    let data = Data((text + "\n").utf8)
    FileHandle.standardError.write(data)
}

enum ChargeError: Error {
    case invalidArguments
    case smcUnavailable
    case unsupportedMachine
    case commandFailed
}

enum ChargeCommand: String {
    case on
    case off
}

enum PowerControl {
    private struct KeyControl {
        let keyInfo: SMCComm.KeyInfo
        let onBytes: [UInt8]
        let offBytes: [UInt8]
    }

    private enum Keys {
        static let chte = SMCComm.KeyInfo(
            key: SMCComm.Key("C", "H", "T", "E"),
            info: SMCComm.KeyInfoData(
                dataSize: 4,
                dataType: SMCComm.KeyTypes.ui32,
                dataAttributes: 0xD4
            )
        )
        static let ch0c = SMCComm.KeyInfo(
            key: SMCComm.Key("C", "H", "0", "C"),
            info: SMCComm.KeyInfoData(
                dataSize: 1,
                dataType: SMCComm.KeyTypes.hex,
                dataAttributes: 0xD4
            )
        )
    }

    private static let chargeKeys = [
        KeyControl(
            keyInfo: Keys.chte,
            onBytes: [0x00, 0x00, 0x00, 0x00],
            offBytes: [0x01, 0x00, 0x00, 0x00]
        ),
        KeyControl(
            keyInfo: Keys.ch0c,
            onBytes: [0x00],
            offBytes: [0x01]
        ),
    ]

    static func run(command: ChargeCommand) throws -> String {
        guard SMCComm.start() else {
            throw ChargeError.smcUnavailable
        }
        defer {
            SMCComm.stop()
        }

        guard let key = chargeKeys.first(where: { SMCComm.keySupported(keyInfo: $0.keyInfo) }) else {
            throw ChargeError.unsupportedMachine
        }

        let targetBytes: [UInt8]
        switch command {
        case .on:
            targetBytes = key.onBytes
        case .off:
            targetBytes = key.offBytes
        }

        let writeResult = SMCComm.writeKey(key: key.keyInfo.key, bytes: targetBytes)
        switch writeResult {
        case .verified:
            break
        case .stateAlreadyMatchedAfterWriteFailure:
            writeChargeStandardError(
                "warning: SMC write call failed, but the charging state is already at the requested target"
            )
        case .failed:
            throw ChargeError.commandFailed
        }

        guard let chargingDisabled = isChargingDisabled(using: key) else {
            throw ChargeError.commandFailed
        }

        switch (command, chargingDisabled) {
        case (.off, true):
            return "charging disabled"
        case (.on, false):
            return "charging enabled"
        default:
            throw ChargeError.commandFailed
        }
    }

    private static func isChargingDisabled(using key: KeyControl) -> Bool? {
        guard let value = SMCComm.readKey(
            key: key.keyInfo.key,
            dataSize: key.onBytes.count
        ) else {
            return nil
        }

        return value != key.onBytes
    }
}

extension ChargeError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "usage: btcharge <on|off>"
        case .smcUnavailable:
            return "failed to open AppleSMC"
        case .unsupportedMachine:
            return "this machine does not expose a supported charging control key"
        case .commandFailed:
            return "failed to update the battery charging state"
        }
    }
}
