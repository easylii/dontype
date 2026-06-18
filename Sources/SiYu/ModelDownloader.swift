import AppKit

/// 下载 whisper 模型（无自带窗口；进度回调给调用方——通常是设置向导 Onboarding 的进度条）。
/// 完成后由调用方拉起 whisper-server；下载期间识别自动走 Apple 后端，不影响使用。
final class ModelDownloader: NSObject, URLSessionDownloadDelegate {
    static let shared = ModelDownloader()

    private var session: URLSession?
    private var succeeded = false
    private var progress: ((Double, String) -> Void)?
    private var finish: ((Bool) -> Void)?

    var isDownloading: Bool { session != nil }

    /// 下载「当前选中的」模型（Whisper.current）。已就绪直接回 true；正在下载则忽略重复调用。
    /// progress：(0~1 进度, 文案)；completion：成功/失败。回调都在主线程。
    func startDownload(progress: @escaping (Double, String) -> Void,
                       completion: @escaping (Bool) -> Void) {
        if Whisper.available { completion(true); return }
        guard session == nil else { return }   // 已在下载中

        self.progress = progress
        self.finish = completion
        self.succeeded = false
        progress(0, L.t(zh: "连接中…", en: "Connecting…"))
        let s = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        session = s
        s.downloadTask(with: Whisper.modelURL).resume()
        FileLog.write("模型下载开始：\(Whisper.modelURL.absoluteString)")
    }

    // MARK: URLSessionDownloadDelegate（delegateQueue = main，可直接回调 UI）

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let done = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let text = String(format: "%.0f / %.0f MB（%.0f%%）",
                          Double(totalBytesWritten) / 1_048_576,
                          Double(totalBytesExpectedToWrite) / 1_048_576,
                          done * 100)
        progress?(done, text)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            try FileManager.default.createDirectory(atPath: Whisper.supportDir,
                                                    withIntermediateDirectories: true)
            let dest = Whisper.supportDir + "/" + Whisper.modelName
            try? FileManager.default.removeItem(atPath: dest)
            try FileManager.default.moveItem(at: location, to: URL(fileURLWithPath: dest))
            succeeded = true
            FileLog.write("模型下载完成：\(dest)")
        } catch {
            FileLog.write("✗ 模型落盘失败：\(error.localizedDescription)")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        defer {
            self.session?.invalidateAndCancel()
            self.session = nil
        }
        if succeeded {
            progress?(1, L.t(zh: "下载完成，识别引擎启动中…", en: "Done. Starting engine…"))
            finish?(true)
        } else {
            let msg = error?.localizedDescription ?? L.t(zh: "下载未完成", en: "Download incomplete")
            progress?(0, L.t(zh: "下载失败：\(msg)（可重试）", en: "Failed: \(msg) (retry)"))
            FileLog.write("✗ 模型下载失败：\(msg)")
            finish?(false)
        }
        progress = nil
        finish = nil
    }
}
