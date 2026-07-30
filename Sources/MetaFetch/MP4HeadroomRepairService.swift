@preconcurrency import AVFoundation
import Foundation

struct MP4HeadroomRepairService: Sendable {
    enum RepairError: LocalizedError {
        case ffmpegUnavailable
        case ffmpegFailed
        case ffmpegTimedOut
        case invalidOutput

        var errorDescription: String? {
            switch self {
            case .ffmpegUnavailable: "Install FFmpeg with Homebrew to reserve MP4 poster headroom automatically."
            case .ffmpegFailed: "FFmpeg could not rebuild this MP4 with reserved metadata space. The original was not changed."
            case .ffmpegTimedOut: "FFmpeg exceeded the two-hour repair limit and was stopped. The original was not changed."
            case .invalidOutput: "The repaired MP4 did not pass validation. The original was not changed."
            }
        }
    }

    private static let trustedExecutablePaths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]

    func repair(fileURL: URL, reservedBytes: Int = 16_777_216) async throws {
        try MediaFileImportValidator.validateStillSafeToWrite(fileURL, expectedIdentity: nil)
        guard let executableURL = try executableURL() else { throw RepairError.ffmpegUnavailable }

        let stagingLocation = try TransactionalFileReplacement.makeStagingLocation(
            for: fileURL,
            pathExtension: "mp4"
        )
        let outputURL = stagingLocation.fileURL
        defer { stagingLocation.remove() }

        let controller = FFmpegProcessController(
            executableURL: executableURL,
            arguments: [
                "-hide_banner", "-loglevel", "error", "-nostdin", "-i", fileURL.path,
                "-map", "0", "-map_metadata", "0", "-c", "copy",
                "-movflags", "+faststart", "-moov_size", String(reservedBytes), "-y", outputURL.path,
            ]
        )
        let status = try await withThrowingTaskGroup(of: Int32.self) { group in
            group.addTask { try await controller.run() }
            group.addTask {
                try await Task.sleep(for: .seconds(7_200))
                throw RepairError.ffmpegTimedOut
            }
            defer {
                group.cancelAll()
                controller.terminate()
            }
            guard let first = try await group.next() else { throw RepairError.ffmpegFailed }
            return first
        }

        guard status == 0 else { throw RepairError.ffmpegFailed }
        let values = try outputURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else { throw RepairError.invalidOutput }

        try await TransactionalFileReplacement.install(preparedFileURL: outputURL, replacing: fileURL) {
            do {
                let asset = AVURLAsset(url: fileURL)
                guard try await asset.load(.isPlayable) else { return false }
                _ = try MP4AtomMetadataWriter().currentMetadataSnapshot(at: fileURL)
                return true
            } catch {
                return false
            }
        }
    }

    private func executableURL() throws -> URL? {
        for path in Self.trustedExecutablePaths {
            let url = URL(fileURLWithPath: path)
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values?.isRegularFile == true,
               values?.isSymbolicLink != true,
               FileManager.default.isExecutableFile(atPath: path) {
                return url
            }
        }
        return nil
    }
}

private final class FFmpegProcessController: @unchecked Sendable {
    private let executableURL: URL
    private let arguments: [String]
    private let lock = NSLock()
    private var process: Process?

    init(executableURL: URL, arguments: [String]) {
        self.executableURL = executableURL
        self.arguments = arguments
    }

    func run() async throws -> Int32 {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        setProcess(process)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { [weak self] completed in
                    self?.setProcess(nil)
                    continuation.resume(returning: completed.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    setProcess(nil)
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            self.terminate()
        }
    }

    func terminate() {
        lock.lock()
        let runningProcess = process
        lock.unlock()
        if runningProcess?.isRunning == true {
            runningProcess?.terminate()
        }
    }

    private func setProcess(_ process: Process?) {
        lock.lock()
        self.process = process
        lock.unlock()
    }
}
