//
// Copyright (C) 2026 NeterOster <neteroster@gmail.com>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import Foundation
import Darwin

private func writeStandardError(_ text: String) {
    let data = Data((text + "\n").utf8)
    FileHandle.standardError.write(data)
}

private func parseCommand(arguments: [String]) throws -> ChargeCommand {
    guard arguments.count == 2, let command = ChargeCommand(rawValue: arguments[1]) else {
        throw ChargeError.invalidArguments
    }

    return command
}

do {
    let command = try parseCommand(arguments: CommandLine.arguments)
    let output = try PowerControl.run(command: command)
    print(output)
    exit(EXIT_SUCCESS)
} catch let error as ChargeError {
    writeStandardError(error.localizedDescription)
    exit(EXIT_FAILURE)
} catch {
    writeStandardError(String(describing: error))
    exit(EXIT_FAILURE)
}
