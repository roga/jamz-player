import Foundation
import AVFoundation
import AudioToolbox

enum MP3Inspector {
    /// Reads bounded PCM chunks to reject mislabeled containers and decoding failures.
    /// Called on the repository actor, never on the UI actor.
    static func duration(of url: URL) throws -> TimeInterval {
        var fileID: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &fileID) == noErr,
              let fileID else { throw ImportError.invalidMP3 }
        defer { AudioFileClose(fileID) }
        var type: AudioFileTypeID = 0
        var size = UInt32(MemoryLayout<AudioFileTypeID>.size)
        guard AudioFileGetProperty(fileID, kAudioFilePropertyFileFormat, &size, &type) == noErr,
              type == kAudioFileMP3Type else { throw ImportError.invalidMP3 }
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            guard format.sampleRate > 0, file.length > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else {
                throw ImportError.invalidMP3
            }
            var frames: Int64 = 0
            while file.framePosition < file.length {
                try Task.checkCancellation()
                try file.read(into: buffer, frameCount: AVAudioFrameCount(min(8192, file.length - file.framePosition)))
                guard buffer.frameLength > 0 else { throw ImportError.invalidMP3 }
                frames += Int64(buffer.frameLength)
            }
            let duration = Double(frames) / format.sampleRate
            guard duration.isFinite, duration > 0 else { throw ImportError.invalidMP3 }
            return duration
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ImportError.invalidMP3
        }
    }
}
