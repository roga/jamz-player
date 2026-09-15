import Foundation

enum LibraryMutationError: LocalizedError {
    case unsupportedTags, missingSong, busy, storage, recovery

    var errorDescription: String? {
        switch self {
        case .unsupportedTags: "此 MP3 的標籤格式無法安全編輯，原檔未變更。"
        case .missingSong: "歌曲已不存在，請重新開啟音樂庫。"
        case .busy: "正在處理音樂庫，請稍後再試。"
        case .storage: "無法更新本機檔案，請確認儲存空間後重試。"
        case .recovery: "音樂庫更新尚未復原，請重新載入後再試。"
        }
    }
}

/// Replace only the three editable text frames. Unsupported ID3 features are
/// rejected before touching the file, rather than risking artwork or audio loss.
enum MP3MetadataWriter {
    static func updating(_ data: Data, title: String, artist: String, album: String) throws -> Data {
        let bytes = [UInt8](data)
        var version: UInt8 = 4
        var audioOffset = 0
        var retained = Data()
        let edited = Set(["TIT2", "TPE1", "TALB"])
        // ID3v1 cannot represent arbitrary Unicode. Do not leave conflicting
        // legacy text behind or silently discard the other legacy fields.
        if bytes.count >= 128, Array(bytes[(bytes.count - 128)..<(bytes.count - 125)]) == Array("TAG".utf8) {
            throw LibraryMutationError.unsupportedTags
        }
        if bytes.starts(with: Array("ID3".utf8)) {
            guard bytes.count >= 10, [3, 4].contains(bytes[3]), bytes[4] == 0, bytes[5] == 0 else {
                throw LibraryMutationError.unsupportedTags
            }
            version = bytes[3]
            let size = try decodeSize(Array(bytes[6..<10]), syncSafe: true)
            guard size <= bytes.count - 10 else { throw LibraryMutationError.unsupportedTags }
            audioOffset = 10 + size
            var offset = 10
            while offset < audioOffset {
                if bytes[offset] == 0 {
                    guard bytes[offset..<audioOffset].allSatisfy({ $0 == 0 }) else { throw LibraryMutationError.unsupportedTags }
                    break
                }
                guard audioOffset - offset >= 10 else { throw LibraryMutationError.unsupportedTags }
                let idBytes = Array(bytes[offset..<(offset + 4)])
                guard idBytes.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }),
                      bytes[offset + 8] == 0, bytes[offset + 9] == 0 else {
                    throw LibraryMutationError.unsupportedTags
                }
                let count = try decodeSize(Array(bytes[(offset + 4)..<(offset + 8)]), syncSafe: version == 4)
                guard count > 0, count <= audioOffset - offset - 10 else { throw LibraryMutationError.unsupportedTags }
                let end = offset + 10 + count
                if !edited.contains(String(decoding: idBytes, as: UTF8.self)) {
                    retained.append(contentsOf: bytes[offset..<end])
                }
                offset = end
            }
        }
        guard audioOffset < bytes.count,
              !bytes[audioOffset...].starts(with: Array("ID3".utf8)) else { throw LibraryMutationError.unsupportedTags }
        for (id, text) in [("TIT2", title), ("TPE1", artist), ("TALB", album)] {
            var payload = Data()
            if version == 3 {
                payload.append(contentsOf: [1, 0xFF, 0xFE])
                for unit in text.utf16 {
                    payload.append(UInt8(unit & 0xFF))
                    payload.append(UInt8(unit >> 8))
                }
            } else {
                payload.append(3)
                payload.append(contentsOf: text.utf8)
            }
            guard !text.contains("\0") else { throw LibraryMutationError.unsupportedTags }
            retained.append(contentsOf: id.utf8)
            retained.append(contentsOf: try encodeSize(payload.count, syncSafe: version == 4))
            retained.append(contentsOf: [0, 0])
            retained.append(payload)
        }
        var result = Data("ID3".utf8)
        result.append(contentsOf: [version, 0, 0])
        result.append(contentsOf: try encodeSize(retained.count, syncSafe: true))
        result.append(retained)
        result.append(contentsOf: bytes[audioOffset...])
        return result
    }

    private static func decodeSize(_ bytes: [UInt8], syncSafe: Bool) throws -> Int {
        guard !syncSafe || bytes.allSatisfy({ $0 < 128 }) else { throw LibraryMutationError.unsupportedTags }
        return bytes.reduce(0) { ($0 << (syncSafe ? 7 : 8)) | Int($1) }
    }

    private static func encodeSize(_ size: Int, syncSafe: Bool) throws -> [UInt8] {
        guard size >= 0, size <= 0x0FFF_FFFF else { throw LibraryMutationError.unsupportedTags }
        let bits = syncSafe ? 7 : 8
        let mask = syncSafe ? 127 : 255
        return (0..<4).reversed().map { UInt8((size >> ($0 * bits)) & mask) }
    }
}
