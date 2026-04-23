import Foundation

struct MP4AtomMetadataWriter: Sendable {
    enum AtomWriterError: LocalizedError {
        case missingMovieAtom
        case invalidAtomLayout
        case atomTooLarge
        case chunkOffsetOverflow
        case fileReadFailed

        var errorDescription: String? {
            switch self {
            case .missingMovieAtom:
                return "MetaFetch could not find the MP4 movie header."
            case .invalidAtomLayout:
                return "MetaFetch could not safely update this MP4 atom layout."
            case .atomTooLarge:
                return "The generated MP4 metadata atom is too large."
            case .chunkOffsetOverflow:
                return "The MP4 uses 32-bit chunk offsets that cannot be adjusted safely."
            case .fileReadFailed:
                return "MetaFetch could not read the full MP4 atom data."
            }
        }
    }

    func writeMetadata(
        to fileURL: URL,
        using result: MediaSearchResult,
        artworkData: Data?,
        progressHandler: (@Sendable (MetadataWriteProgress) async -> Void)? = nil
    ) async throws {
        await progressHandler?(MetadataWriteProgress(
            fractionCompleted: 0.12,
            message: "Reading MP4 movie header"
        ))

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        let fileSize = try handle.seekToEnd()
        let topLevelBoxes = try readTopLevelBoxes(from: handle, fileSize: fileSize)

        guard let movieBox = topLevelBoxes.first(where: { $0.type == .moov }) else {
            throw AtomWriterError.missingMovieAtom
        }

        let followingFreeBox = topLevelBoxes.first {
            $0.start == movieBox.end && $0.type == .free
        }
        let reservedEnd = followingFreeBox?.end ?? movieBox.end
        let oldReservedSize = reservedEnd - movieBox.start

        try handle.seek(toOffset: movieBox.start)
        let movieAtomData = handle.readData(ofLength: Int(movieBox.size))
        guard UInt64(movieAtomData.count) == movieBox.size else {
            throw AtomWriterError.fileReadFailed
        }
        try handle.close()

        var updatedMovieAtom = try updatedMovieAtom(
            from: movieAtomData,
            headerSize: Int(movieBox.headerSize),
            result: result,
            artworkData: artworkData
        )

        await progressHandler?(MetadataWriteProgress(
            fractionCompleted: 0.34,
            message: "Checking MP4 metadata headroom"
        ))

        if try await writeInPlaceIfPossible(
            updatedMovieAtom,
            to: fileURL,
            movieBox: movieBox,
            oldReservedSize: oldReservedSize,
            progressHandler: progressHandler
        ) {
            return
        }

        await progressHandler?(MetadataWriteProgress(
            fractionCompleted: 0.42,
            message: "Adjusting MP4 chunk map for metadata growth"
        ))

        let delta = Int64(updatedMovieAtom.count) - Int64(oldReservedSize)
        if delta != 0 {
            try adjustChunkOffsets(
                in: &updatedMovieAtom,
                oldReservedEnd: reservedEnd,
                delta: delta
            )
        }

        await progressHandler?(MetadataWriteProgress(
            fractionCompleted: 0.5,
            message: "Rebuilding MP4 container without re-encoding"
        ))

        try await rewriteFile(
            at: fileURL,
            topLevelBoxes: topLevelBoxes,
            movieBox: movieBox,
            followingFreeBox: followingFreeBox,
            updatedMovieAtom: updatedMovieAtom,
            progressHandler: progressHandler
        )
    }

    private func writeInPlaceIfPossible(
        _ updatedMovieAtom: Data,
        to fileURL: URL,
        movieBox: MP4FileAtom,
        oldReservedSize: UInt64,
        progressHandler: (@Sendable (MetadataWriteProgress) async -> Void)?
    ) async throws -> Bool {
        let newSize = UInt64(updatedMovieAtom.count)
        guard newSize <= oldReservedSize else {
            return false
        }

        let leftoverSize = oldReservedSize - newSize
        guard leftoverSize == 0 || leftoverSize >= MP4FileAtom.minimumHeaderSize else {
            return false
        }

        await progressHandler?(MetadataWriteProgress(
            fractionCompleted: 0.56,
            message: "Writing metadata into existing MP4 header space"
        ))

        let handle = try FileHandle(forUpdating: fileURL)
        defer {
            try? handle.close()
        }

        try handle.seek(toOffset: movieBox.start)
        try handle.write(contentsOf: updatedMovieAtom)

        if leftoverSize > 0 {
            try handle.write(contentsOf: makeFreeAtom(byteCount: Int(leftoverSize)))
        }

        try handle.synchronize()

        await progressHandler?(MetadataWriteProgress(
            fractionCompleted: 0.82,
            message: "Finished metadata header update"
        ))

        return true
    }

    private func rewriteFile(
        at fileURL: URL,
        topLevelBoxes: [MP4FileAtom],
        movieBox: MP4FileAtom,
        followingFreeBox: MP4FileAtom?,
        updatedMovieAtom: Data,
        progressHandler: (@Sendable (MetadataWriteProgress) async -> Void)?
    ) async throws {
        let temporaryURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(".\(fileURL.lastPathComponent).metafetch-\(UUID().uuidString).tmp")

        _ = FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)

        let input = try FileHandle(forReadingFrom: fileURL)
        let output = try FileHandle(forWritingTo: temporaryURL)
        var didFinish = false

        defer {
            try? input.close()
            try? output.close()

            if !didFinish {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
        }

        let totalBytesToCopy = topLevelBoxes.reduce(UInt64(0)) { partialResult, atom in
            if atom.start == movieBox.start {
                return partialResult + UInt64(updatedMovieAtom.count)
            }

            if followingFreeBox?.start == atom.start {
                return partialResult
            }

            return partialResult + atom.size
        }

        var copiedBytes = UInt64(0)

        for atom in topLevelBoxes {
            if atom.start == movieBox.start {
                try output.write(contentsOf: updatedMovieAtom)
                copiedBytes += UInt64(updatedMovieAtom.count)
            } else if followingFreeBox?.start == atom.start {
                continue
            } else {
                try await copyRange(
                    start: atom.start,
                    length: atom.size,
                    from: input,
                    to: output,
                    copiedBytes: &copiedBytes,
                    totalBytesToCopy: totalBytesToCopy,
                    progressHandler: progressHandler
                )
            }
        }

        try output.synchronize()
        try output.close()
        try input.close()

        _ = try FileManager.default.replaceItemAt(
            fileURL,
            withItemAt: temporaryURL,
            backupItemName: nil,
            options: []
        )
        didFinish = true
    }

    private func copyRange(
        start: UInt64,
        length: UInt64,
        from input: FileHandle,
        to output: FileHandle,
        copiedBytes: inout UInt64,
        totalBytesToCopy: UInt64,
        progressHandler: (@Sendable (MetadataWriteProgress) async -> Void)?
    ) async throws {
        try input.seek(toOffset: start)

        var remaining = length
        let chunkSize: UInt64 = 4 * 1024 * 1024

        while remaining > 0 {
            let bytesToRead = Int(min(chunkSize, remaining))
            let chunk = input.readData(ofLength: bytesToRead)
            guard !chunk.isEmpty else {
                throw AtomWriterError.fileReadFailed
            }

            try output.write(contentsOf: chunk)
            remaining -= UInt64(chunk.count)
            copiedBytes += UInt64(chunk.count)

            if totalBytesToCopy > 0 {
                let fraction = 0.5 + (Double(copiedBytes) / Double(totalBytesToCopy) * 0.34)
                await progressHandler?(MetadataWriteProgress(
                    fractionCompleted: fraction,
                    message: "Copying MP4 container data"
                ))
            }
        }
    }

    private func updatedMovieAtom(
        from movieAtomData: Data,
        headerSize: Int,
        result: MediaSearchResult,
        artworkData: Data?
    ) throws -> Data {
        guard movieAtomData.count >= headerSize else {
            throw AtomWriterError.invalidAtomLayout
        }

        let moviePayload = movieAtomData.subdata(in: headerSize..<movieAtomData.count)
        let metadataItems = makeMetadataItemAtoms(for: result, artworkData: artworkData)
        let updatedPayload = try updateMoviePayload(moviePayload, metadataItems: metadataItems)

        return try makeAtom(type: .moov, payload: updatedPayload)
    }

    private func updateMoviePayload(
        _ moviePayload: Data,
        metadataItems: [Data]
    ) throws -> Data {
        let boxes = try parseAtoms(in: moviePayload, range: 0..<moviePayload.count)
        let metadataAtom = try makeMetadataAtom(with: metadataItems)

        if let userDataBox = boxes.first(where: { $0.type == .udta }) {
            let updatedUserDataAtom = try updatedUserDataAtom(
                userDataBox,
                in: moviePayload,
                metadataAtom: metadataAtom
            )
            return replacing(userDataBox.fullRange, in: moviePayload, with: updatedUserDataAtom)
        }

        var updatedPayload = moviePayload
        updatedPayload.append(try makeAtom(type: .udta, payload: metadataAtom))
        return updatedPayload
    }

    private func updatedUserDataAtom(
        _ userDataBox: MP4MemoryAtom,
        in moviePayload: Data,
        metadataAtom: Data
    ) throws -> Data {
        let userDataPayload = moviePayload.subdata(in: userDataBox.payloadRange)
        let boxes = try parseAtoms(in: userDataPayload, range: 0..<userDataPayload.count)

        if let metaBox = boxes.first(where: { $0.type == .meta }) {
            return try makeAtom(
                type: .udta,
                payload: replacing(metaBox.fullRange, in: userDataPayload, with: metadataAtom)
            )
        }

        var updatedPayload = userDataPayload
        updatedPayload.append(metadataAtom)
        return try makeAtom(type: .udta, payload: updatedPayload)
    }

    private func makeMetadataAtom(with metadataItems: [Data]) throws -> Data {
        var ilstPayload = Data()
        for item in metadataItems {
            ilstPayload.append(item)
        }

        var payload = Data()
        payload.append(makeUInt32Data(0))
        payload.append(try makeHandlerAtom())
        payload.append(try makeAtom(type: .ilst, payload: ilstPayload))
        return try makeAtom(type: .meta, payload: payload)
    }

    private func makeHandlerAtom() throws -> Data {
        var payload = Data()
        payload.append(makeUInt32Data(0))
        payload.append(makeUInt32Data(0))
        payload.append(contentsOf: MP4AtomType.mdir.bytes)
        payload.append(contentsOf: MP4AtomType.appl.bytes)
        payload.append(makeUInt32Data(0))
        payload.append(makeUInt32Data(0))
        payload.append(contentsOf: [0])
        return try makeAtom(type: .hdlr, payload: payload)
    }

    private func makeMetadataItemAtoms(
        for result: MediaSearchResult,
        artworkData: Data?
    ) -> [Data] {
        var atoms: [Data] = []

        appendTextAtom(.name, value: result.trackName, to: &atoms)

        let synopsis = result.synopsis.trimmingCharacters(in: .whitespacesAndNewlines)
        appendTextAtom(.description, value: synopsis, to: &atoms)
        appendTextAtom(.longDescription, value: synopsis, to: &atoms)

        appendTextAtom(.genre, value: result.primaryGenreName, to: &atoms)
        appendTextAtom(.releaseDate, value: result.releaseYear ?? result.releaseDate, to: &atoms)

        if let creator = result.creatorValue {
            appendTextAtom(.artist, value: creator, to: &atoms)
            appendTextAtom(.albumArtist, value: creator, to: &atoms)
        }

        switch result.mediaKind {
        case .movie:
            appendIntegerAtom(.mediaKind, value: 9, byteCount: 1, to: &atoms)
        case .tvEpisode:
            let showName = result.seriesName?.trimmedNilIfBlank
            appendTextAtom(.tvShow, value: showName, to: &atoms)
            appendTextAtom(.album, value: showName, to: &atoms)
            appendTextAtom(.episodeId, value: result.seasonEpisodeLabel, to: &atoms)
            appendIntegerAtom(.mediaKind, value: 10, byteCount: 1, to: &atoms)

            if let seasonNumber = result.seasonNumber {
                appendIntegerAtom(.tvSeason, value: seasonNumber, byteCount: 4, to: &atoms)
            }

            if let episodeNumber = result.episodeNumber {
                appendIntegerAtom(.tvEpisode, value: episodeNumber, byteCount: 4, to: &atoms)
            }
        case .tvSeries:
            appendTextAtom(.tvShow, value: result.trackName, to: &atoms)
            appendTextAtom(.album, value: result.trackName, to: &atoms)
            appendIntegerAtom(.mediaKind, value: 10, byteCount: 1, to: &atoms)
        }

        let comments = comments(for: result)
        appendTextAtom(.comment, value: comments, to: &atoms)

        if let artworkData, !artworkData.isEmpty,
           let atom = try? makeMetadataDataAtom(
            type: .coverArt,
            dataType: artworkData.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? 14 : 13,
            payload: artworkData
           ) {
            atoms.append(atom)
        }

        return atoms
    }

    private func appendTextAtom(_ type: MP4AtomType, value: String?, to atoms: inout [Data]) {
        guard let value = value?.trimmedNilIfBlank,
              let payload = value.data(using: .utf8),
              let atom = try? makeMetadataDataAtom(type: type, dataType: 1, payload: payload) else {
            return
        }

        atoms.append(atom)
    }

    private func appendIntegerAtom(
        _ type: MP4AtomType,
        value: Int,
        byteCount: Int,
        to atoms: inout [Data]
    ) {
        guard value >= 0 else {
            return
        }

        var payload = makeUInt64Data(UInt64(value))
        payload = Data(payload.suffix(byteCount))

        guard let atom = try? makeMetadataDataAtom(type: type, dataType: 21, payload: payload) else {
            return
        }

        atoms.append(atom)
    }

    private func comments(for result: MediaSearchResult) -> String? {
        var lines: [String] = []

        if let label = result.seasonEpisodeLabel {
            lines.append("Episode: \(label)")
        }

        if let rating = result.contentAdvisoryRating?.trimmedNilIfBlank {
            lines.append("Rating: \(rating)")
        }

        lines.append("Tagged by MetaFetch from \(result.sourceName)")

        return lines.joined(separator: "\n")
    }

    private func makeMetadataDataAtom(
        type: MP4AtomType,
        dataType: UInt32,
        payload: Data
    ) throws -> Data {
        var dataPayload = Data()
        dataPayload.append(makeUInt32Data(dataType))
        dataPayload.append(makeUInt32Data(0))
        dataPayload.append(payload)

        return try makeAtom(type: type, payload: makeAtom(type: .data, payload: dataPayload))
    }

    private func readTopLevelBoxes(
        from handle: FileHandle,
        fileSize: UInt64
    ) throws -> [MP4FileAtom] {
        var atoms: [MP4FileAtom] = []
        var offset: UInt64 = 0

        while offset + MP4FileAtom.minimumHeaderSize <= fileSize {
            try handle.seek(toOffset: offset)
            let headerData = handle.readData(ofLength: 16)
            guard headerData.count >= Int(MP4FileAtom.minimumHeaderSize) else {
                throw AtomWriterError.fileReadFailed
            }

            let size32 = readUInt32(headerData, at: 0)
            let type = MP4AtomType(data: headerData, offset: 4)
            var headerSize = MP4FileAtom.minimumHeaderSize
            var size = UInt64(size32)

            if size32 == 1 {
                guard headerData.count >= 16 else {
                    throw AtomWriterError.fileReadFailed
                }

                size = readUInt64(headerData, at: 8)
                headerSize = 16
            } else if size32 == 0 {
                size = fileSize - offset
            }

            guard size >= headerSize,
                  offset + size <= fileSize else {
                throw AtomWriterError.invalidAtomLayout
            }

            atoms.append(MP4FileAtom(
                type: type,
                start: offset,
                size: size,
                headerSize: headerSize
            ))

            offset += size
        }

        return atoms
    }

    private func parseAtoms(in data: Data, range: Range<Int>) throws -> [MP4MemoryAtom] {
        var atoms: [MP4MemoryAtom] = []
        var offset = range.lowerBound

        while offset < range.upperBound {
            let remaining = range.upperBound - offset
            guard remaining >= Int(MP4FileAtom.minimumHeaderSize) else {
                if data[offset..<range.upperBound].allSatisfy({ $0 == 0 }) {
                    break
                }

                throw AtomWriterError.invalidAtomLayout
            }

            let size32 = readUInt32(data, at: offset)
            let type = MP4AtomType(data: data, offset: offset + 4)
            var headerSize = Int(MP4FileAtom.minimumHeaderSize)
            var size = UInt64(size32)

            if size32 == 1 {
                guard remaining >= 16 else {
                    throw AtomWriterError.invalidAtomLayout
                }

                size = readUInt64(data, at: offset + 8)
                headerSize = 16
            } else if size32 == 0 {
                size = UInt64(remaining)
            }

            guard size >= UInt64(headerSize),
                  size <= UInt64(remaining) else {
                throw AtomWriterError.invalidAtomLayout
            }

            let end = offset + Int(size)
            atoms.append(MP4MemoryAtom(
                type: type,
                fullRange: offset..<end,
                payloadRange: (offset + headerSize)..<end
            ))

            offset = end
        }

        return atoms
    }

    private func replacing(_ range: Range<Int>, in data: Data, with replacement: Data) -> Data {
        var updated = data
        updated.replaceSubrange(range, with: replacement)
        return updated
    }

    private func makeAtom(type: MP4AtomType, payload: Data) throws -> Data {
        let size = UInt64(payload.count) + MP4FileAtom.minimumHeaderSize
        guard size <= UInt64(UInt32.max) else {
            throw AtomWriterError.atomTooLarge
        }

        var data = Data()
        data.append(makeUInt32Data(UInt32(size)))
        data.append(contentsOf: type.bytes)
        data.append(payload)
        return data
    }

    private func makeFreeAtom(byteCount: Int) throws -> Data {
        guard byteCount >= Int(MP4FileAtom.minimumHeaderSize) else {
            throw AtomWriterError.invalidAtomLayout
        }

        return try makeAtom(type: .free, payload: Data(count: byteCount - Int(MP4FileAtom.minimumHeaderSize)))
    }

    private func adjustChunkOffsets(
        in movieAtomData: inout Data,
        oldReservedEnd: UInt64,
        delta: Int64
    ) throws {
        let root = try parseAtoms(in: movieAtomData, range: 0..<movieAtomData.count)
        guard let movieAtom = root.first,
              movieAtom.type == .moov else {
            throw AtomWriterError.invalidAtomLayout
        }

        try adjustChunkOffsets(
            in: &movieAtomData,
            atom: movieAtom,
            oldReservedEnd: oldReservedEnd,
            delta: delta
        )
    }

    private func adjustChunkOffsets(
        in data: inout Data,
        atom: MP4MemoryAtom,
        oldReservedEnd: UInt64,
        delta: Int64
    ) throws {
        if atom.type == .stco {
            try adjustStco(in: &data, atom: atom, oldReservedEnd: oldReservedEnd, delta: delta)
            return
        }

        if atom.type == .co64 {
            try adjustCo64(in: &data, atom: atom, oldReservedEnd: oldReservedEnd, delta: delta)
            return
        }

        guard atom.type.isContainer else {
            return
        }

        let childRange: Range<Int>
        if atom.type == .meta {
            guard atom.payloadRange.count >= 4 else {
                throw AtomWriterError.invalidAtomLayout
            }
            childRange = (atom.payloadRange.lowerBound + 4)..<atom.payloadRange.upperBound
        } else {
            childRange = atom.payloadRange
        }

        let children = try parseAtoms(in: data, range: childRange)
        for child in children {
            try adjustChunkOffsets(
                in: &data,
                atom: child,
                oldReservedEnd: oldReservedEnd,
                delta: delta
            )
        }
    }

    private func adjustStco(
        in data: inout Data,
        atom: MP4MemoryAtom,
        oldReservedEnd: UInt64,
        delta: Int64
    ) throws {
        guard atom.payloadRange.count >= 8 else {
            throw AtomWriterError.invalidAtomLayout
        }

        let entryCount = Int(readUInt32(data, at: atom.payloadRange.lowerBound + 4))
        var offset = atom.payloadRange.lowerBound + 8

        guard offset + (entryCount * 4) <= atom.payloadRange.upperBound else {
            throw AtomWriterError.invalidAtomLayout
        }

        for _ in 0..<entryCount {
            let oldOffset = UInt64(readUInt32(data, at: offset))
            if oldOffset >= oldReservedEnd {
                let adjusted = Int64(oldOffset) + delta
                guard adjusted >= 0,
                      adjusted <= Int64(UInt32.max) else {
                    throw AtomWriterError.chunkOffsetOverflow
                }

                writeUInt32(UInt32(adjusted), to: &data, at: offset)
            }

            offset += 4
        }
    }

    private func adjustCo64(
        in data: inout Data,
        atom: MP4MemoryAtom,
        oldReservedEnd: UInt64,
        delta: Int64
    ) throws {
        guard atom.payloadRange.count >= 8 else {
            throw AtomWriterError.invalidAtomLayout
        }

        let entryCount = Int(readUInt32(data, at: atom.payloadRange.lowerBound + 4))
        var offset = atom.payloadRange.lowerBound + 8

        guard offset + (entryCount * 8) <= atom.payloadRange.upperBound else {
            throw AtomWriterError.invalidAtomLayout
        }

        for _ in 0..<entryCount {
            let oldOffset = readUInt64(data, at: offset)
            if oldOffset >= oldReservedEnd {
                let adjusted = Int64(oldOffset) + delta
                guard adjusted >= 0 else {
                    throw AtomWriterError.chunkOffsetOverflow
                }

                writeUInt64(UInt64(adjusted), to: &data, at: offset)
            }

            offset += 8
        }
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24 |
            UInt32(data[offset + 1]) << 16 |
            UInt32(data[offset + 2]) << 8 |
            UInt32(data[offset + 3])
    }

    private func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        UInt64(readUInt32(data, at: offset)) << 32 |
            UInt64(readUInt32(data, at: offset + 4))
    }

    private func writeUInt32(_ value: UInt32, to data: inout Data, at offset: Int) {
        data.replaceSubrange(offset..<(offset + 4), with: makeUInt32Data(value))
    }

    private func writeUInt64(_ value: UInt64, to data: inout Data, at offset: Int) {
        data.replaceSubrange(offset..<(offset + 8), with: makeUInt64Data(value))
    }

    private func makeUInt32Data(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    private func makeUInt64Data(_ value: UInt64) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}

private struct MP4FileAtom: Sendable {
    static let minimumHeaderSize: UInt64 = 8

    let type: MP4AtomType
    let start: UInt64
    let size: UInt64
    let headerSize: UInt64

    var end: UInt64 {
        start + size
    }
}

private struct MP4MemoryAtom: Sendable {
    let type: MP4AtomType
    let fullRange: Range<Int>
    let payloadRange: Range<Int>
}

private struct MP4AtomType: Hashable, Sendable {
    let bytes: [UInt8]

    init(ascii: String) {
        self.bytes = Array(ascii.utf8)
    }

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    init(data: Data, offset: Int) {
        self.bytes = Array(data[offset..<(offset + 4)])
    }

    static let album = MP4AtomType(bytes: [0xA9, 0x61, 0x6C, 0x62])
    static let albumArtist = MP4AtomType(ascii: "aART")
    static let appl = MP4AtomType(ascii: "appl")
    static let artist = MP4AtomType(bytes: [0xA9, 0x41, 0x52, 0x54])
    static let co64 = MP4AtomType(ascii: "co64")
    static let comment = MP4AtomType(bytes: [0xA9, 0x63, 0x6D, 0x74])
    static let coverArt = MP4AtomType(ascii: "covr")
    static let data = MP4AtomType(ascii: "data")
    static let description = MP4AtomType(ascii: "desc")
    static let dinf = MP4AtomType(ascii: "dinf")
    static let edts = MP4AtomType(ascii: "edts")
    static let episodeId = MP4AtomType(ascii: "tven")
    static let free = MP4AtomType(ascii: "free")
    static let genre = MP4AtomType(bytes: [0xA9, 0x67, 0x65, 0x6E])
    static let hdlr = MP4AtomType(ascii: "hdlr")
    static let ilst = MP4AtomType(ascii: "ilst")
    static let longDescription = MP4AtomType(ascii: "ldes")
    static let mdia = MP4AtomType(ascii: "mdia")
    static let mediaKind = MP4AtomType(ascii: "stik")
    static let meta = MP4AtomType(ascii: "meta")
    static let mdir = MP4AtomType(ascii: "mdir")
    static let minf = MP4AtomType(ascii: "minf")
    static let moov = MP4AtomType(ascii: "moov")
    static let name = MP4AtomType(bytes: [0xA9, 0x6E, 0x61, 0x6D])
    static let releaseDate = MP4AtomType(bytes: [0xA9, 0x64, 0x61, 0x79])
    static let stbl = MP4AtomType(ascii: "stbl")
    static let stco = MP4AtomType(ascii: "stco")
    static let trak = MP4AtomType(ascii: "trak")
    static let tvEpisode = MP4AtomType(ascii: "tves")
    static let tvSeason = MP4AtomType(ascii: "tvsn")
    static let tvShow = MP4AtomType(ascii: "tvsh")
    static let udta = MP4AtomType(ascii: "udta")

    var isContainer: Bool {
        Self.containerTypes.contains(self)
    }

    private static let containerTypes: Set<MP4AtomType> = [
        .dinf,
        .edts,
        .mdia,
        .meta,
        .minf,
        .moov,
        .stbl,
        .trak,
        .udta,
    ]
}

private extension String {
    var trimmedNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
