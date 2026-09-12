import Foundation

struct DDCError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

actor DDCClient {
    private var toolURL: URL {
        if let bundled = Bundle.main.url(forResource: "monitor-ddc", withExtension: nil) {
            return bundled
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/monitor-ddc")
    }

    func displays() throws -> [MonitorDisplay] {
        let data = try run(["list"])
        return try JSONDecoder().decode([MonitorDisplay].self, from: data)
    }

    func read(display: Int, code: Int) throws -> VCPReading {
        let data = try run(["read", String(display), String(code)])
        return try JSONDecoder().decode(VCPReading.self, from: data)
    }

    func scan(display: Int) throws -> [VCPReading] {
        let data = try run(["scan", String(display)])
        return try JSONDecoder().decode([VCPReading].self, from: data)
    }

    func write(display: Int, code: Int, value: Int, dataAddress: Int = 0x51) throws {
        _ = try run([
            "write", String(display), String(code), String(value), String(dataAddress)
        ])
    }

    private func run(_ arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = toolURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw DDCError(message: "Could not start the bundled DDC helper: \(error.localizedDescription)")
        }
        process.waitUntilExit()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw DDCError(message: detail?.isEmpty == false ? detail! : "The monitor rejected the command.")
        }
        return outputData
    }
}
