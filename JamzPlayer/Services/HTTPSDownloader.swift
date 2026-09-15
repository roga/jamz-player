import Foundation

enum ImportError: LocalizedError {
    case httpsRequired, httpStatus(Int), invalidMP3, storage, libraryUnavailable

    var errorDescription: String? {
        switch self {
        case .httpsRequired: return "請輸入有效的 HTTPS MP3 直連網址，轉址也必須使用 HTTPS。"
        case .httpStatus(let code): return "伺服器無法提供音檔（HTTP \(code)），請確認網址。"
        case .invalidMP3: return "這個檔案不是可播放的 MP3，或音檔已損毀。"
        case .storage: return "無法儲存音樂，請確認手機的可用空間後重試。"
        case .libraryUnavailable: return "無法讀取音樂庫。為保留既有資料，暫時停止匯入，請重新開啟 App。"
        }
    }

    static func message(for error: Error) -> String {
        if let known = error as? ImportError { return known.localizedDescription }
        if let network = error as? URLError {
            switch network.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "網路連線已中斷，請連上網路後重新下載。"
            case .timedOut:
                return "下載逾時，請稍後再試。"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "無法連線至下載伺服器，請確認網址是否正確。"
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                return "無法驗證伺服器的 HTTPS 安全連線，請改用有效的下載網址。"
            default: return "下載失敗，請檢查網路與網址後重試。"
            }
        }
        return "匯入失敗，請確認手機的可用空間與音檔後重試。"
    }
}

enum HTTPSURLPolicy {
    static func validate(_ text: String) throws -> URL {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { throw ImportError.httpsRequired }
        return url
    }
}

struct DownloadedFile: Sendable {
    let url: URL
    let suggestedName: String
}

/// One operation per import. The lock protects cancellation against delegate callbacks.
final class HTTPSDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<DownloadedFile, Error>?
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var cancelled = false
    private var finished = false
    private let progress: @Sendable (Double?) -> Void
    private let configuration: URLSessionConfiguration

    init(configuration: URLSessionConfiguration = .ephemeral, progress: @escaping @Sendable (Double?) -> Void) {
        self.configuration = configuration.copy() as! URLSessionConfiguration
        self.progress = progress
    }

    func download(from url: URL) async throws -> DownloadedFile {
        _ = try HTTPSURLPolicy.validate(url.absoluteString)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                configuration.timeoutIntervalForRequest = 60
                configuration.timeoutIntervalForResource = 3600
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                let task = session.downloadTask(with: url)
                self.task = task
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func cancel() {
        lock.lock()
        cancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
        finish(.failure(CancellationError()))
    }

    @discardableResult
    private func finish(_ result: Result<DownloadedFile, Error>) -> Bool {
        lock.lock()
        guard !finished, let continuation else { lock.unlock(); return false }
        finished = true
        self.continuation = nil
        let session = session
        self.session = nil
        task = nil
        lock.unlock()
        continuation.resume(with: result)
        session?.invalidateAndCancel()
        return true
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, (try? HTTPSURLPolicy.validate(url.absoluteString)) != nil else {
            completionHandler(nil)
            finish(.failure(ImportError.httpsRequired))
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        progress(totalBytesExpectedToWrite > 0
                 ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) : nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let response = downloadTask.response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            finish(.failure(ImportError.httpStatus((downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0)))
            return
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("jamz-\(UUID().uuidString).mp3")
        do {
            // URLSession removes location after this callback, so move synchronously.
            try FileManager.default.moveItem(at: location, to: destination)
            let file = DownloadedFile(url: destination, suggestedName: response.suggestedFilename ?? "未命名.mp3")
            if !finish(.success(file)) { try? FileManager.default.removeItem(at: destination) }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            finish(.failure(ImportError.storage))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
}
