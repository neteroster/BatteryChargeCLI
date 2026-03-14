//
// Copyright (C) 2026 NeterOster <neteroster@gmail.com>. All rights reserved.
// Derived from Battery-Toolkit by Marvin Häuser (BSD-3-Clause).
// SPDX-License-Identifier: BSD-3-Clause
//

import CSMCHelpers
import Foundation
import IOKit

private func writeSMCStandardError(_ text: String) {
    let data = Data((text + "\n").utf8)
    FileHandle.standardError.write(data)
}

private func uint32FromBytes(
    _ byte0: UInt8,
    _ byte1: UInt8,
    _ byte2: UInt8,
    _ byte3: UInt8
) -> UInt32 {
    let comp0 = UInt32(byte0) << 24
    let comp1 = UInt32(byte1) << 16
    let comp2 = UInt32(byte2) << 8
    let comp3 = UInt32(byte3)
    return comp0 | comp1 | comp2 | comp3
}

typealias SMCId = UInt32

extension SMCId {
    init(
        _ char0: Character,
        _ char1: Character,
        _ char2: Character,
        _ char3: Character
    ) {
        precondition(char0.isASCII && char1.isASCII && char2.isASCII && char3.isASCII)
        self = uint32FromBytes(
            char0.asciiValue!,
            char1.asciiValue!,
            char2.asciiValue!,
            char3.asciiValue!
        )
    }
}

enum SMCComm {
    enum WriteResult {
        case verified
        case stateAlreadyMatchedAfterWriteFailure
        case failed
    }

    typealias Key = SMCId
    typealias KeyType = SMCId
    typealias KeyInfoData = SMCKeyInfoData

    struct KeyInfo {
        let key: Key
        let info: KeyInfoData
    }

    enum KeyTypes {
        static let ui8 = KeyType("u", "i", "8", " ")
        static let ui32 = KeyType("u", "i", "3", "2")
        static let hex = KeyType("h", "e", "x", "_")
    }

    private static var connect = IO_OBJECT_NULL

    static func start() -> Bool {
        precondition(connect == IO_OBJECT_NULL)

        let smc = IOServiceGetMatchingService(
            kIOMasterPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard smc != IO_OBJECT_NULL else {
            return false
        }

        var newConnection: io_connect_t = IO_OBJECT_NULL
        let resultOpen = IOServiceOpen(
            smc,
            get_mach_task_self(),
            1,
            &newConnection
        )
        IOObjectRelease(smc)

        guard resultOpen == kIOReturnSuccess, newConnection != IO_OBJECT_NULL else {
            return false
        }

        let resultUserClientOpen = IOConnectCallMethod(
            newConnection,
            UInt32(kSMCUserClientOpen),
            nil,
            0,
            nil,
            0,
            nil,
            nil,
            nil,
            nil
        )

        guard resultUserClientOpen == kIOReturnSuccess else {
            writeSMCStandardError(
                "SMC user client open error: IOKit=\(resultUserClientOpen)"
            )
            IOServiceClose(newConnection)
            return false
        }

        connect = newConnection

        return true
    }

    static func stop() {
        precondition(connect != IO_OBJECT_NULL)

        _ = IOConnectCallMethod(
            connect,
            UInt32(kSMCUserClientClose),
            nil,
            0,
            nil,
            0,
            nil,
            nil,
            nil,
            nil
        )
        IOServiceClose(connect)
        connect = IO_OBJECT_NULL
    }

    static func keySupported(keyInfo: KeyInfo) -> Bool {
        guard let info = getKeyInfo(key: keyInfo.key) else {
            return false
        }

        return keyInfoDataEqual(lhs: keyInfo.info, rhs: info)
    }

    static func readKey(key: Key, dataSize: Int) -> [UInt8]? {
        var inputStruct = SMCParamStruct.readKey(
            key: key,
            dataSize: UInt32(dataSize)
        )

        guard let outputStruct = callSMCFunctionYPC(params: &inputStruct) else {
            return nil
        }

        return withUnsafeBytes(of: outputStruct.bytes) { rawBuffer in
            Array(rawBuffer.prefix(dataSize))
        }
    }

    static func writeKey(key: Key, bytes: [UInt8]) -> WriteResult {
        var inputStruct = SMCParamStruct.writeKey(key: key, bytes: bytes)
        let writeSucceeded = callSMCFunctionYPC(params: &inputStruct) != nil
        guard let readValue = readKey(key: key, dataSize: bytes.count) else {
            return .failed
        }

        guard readValue == bytes else {
            return .failed
        }

        return writeSucceeded ? .verified : .stateAlreadyMatchedAfterWriteFailure
    }

    private static func getKeyInfo(key: Key) -> KeyInfoData? {
        var inputStruct = SMCParamStruct.info(key: key)
        guard let outputStruct = callSMCFunctionYPC(params: &inputStruct) else {
            return nil
        }

        return outputStruct.keyInfo
    }

    private static func keyInfoDataEqual(lhs: KeyInfoData, rhs: KeyInfoData) -> Bool {
        lhs.dataSize == rhs.dataSize &&
            lhs.dataType == rhs.dataType &&
            lhs.dataAttributes == rhs.dataAttributes
    }

    private static func callSMCFunctionYPC(
        params: inout SMCParamStruct
    ) -> SMCParamStruct? {
        precondition(connect != IO_OBJECT_NULL)
        precondition(MemoryLayout<SMCParamStruct>.stride == 80)

        var outputValues = SMCParamStruct.output()
        var outStructSize = MemoryLayout<SMCParamStruct>.stride

        let resultCall = IOConnectCallStructMethod(
            connect,
            UInt32(kSMCHandleYPCEvent),
            &params,
            MemoryLayout<SMCParamStruct>.stride,
            &outputValues,
            &outStructSize
        )

        guard
            resultCall == kIOReturnSuccess,
            outputValues.result == UInt8(kSMCSuccess)
        else {
            writeSMCStandardError(
                "SMC error: IOKit=\(resultCall), result=\(outputValues.result)"
            )
            return nil
        }

        return outputValues
    }
}

private extension SMCParamStruct {
    static func info(key: SMCComm.Key) -> SMCParamStruct {
        var paramStruct = SMCParamStruct()
        paramStruct.key = key
        paramStruct.data8 = UInt8(kSMCGetKeyInfo)
        return paramStruct
    }

    static func readKey(key: SMCComm.Key, dataSize: UInt32) -> SMCParamStruct {
        var paramStruct = SMCParamStruct()
        paramStruct.key = key
        paramStruct.keyInfo.dataSize = dataSize
        paramStruct.data8 = UInt8(kSMCReadKey)
        return paramStruct
    }

    static func writeKey(key: SMCComm.Key, bytes: [UInt8]) -> SMCParamStruct {
        precondition(bytes.count <= 32)

        var paramStruct = SMCParamStruct()
        paramStruct.key = key
        paramStruct.keyInfo.dataSize = UInt32(bytes.count)
        paramStruct.data8 = UInt8(kSMCWriteKey)

        _ = withUnsafeMutablePointer(to: &paramStruct.bytes) { pointer in
            memcpy(pointer, bytes, bytes.count)
        }

        return paramStruct
    }

    static func output() -> SMCParamStruct {
        SMCParamStruct()
    }
}
