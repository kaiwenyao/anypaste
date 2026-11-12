import Combine
import Foundation

/// A parsed release version such as "1.1.0" or "v1.1.0".
///
/// GitHub release tags use a leading "v", the bundle's
/// `CFBundleShortVersionString` does not, and the build number
/// (`CFBundleVersion`) is not part of the tag. Only the numeric release
/// version is compared here.
struct VersionNumber: Comparable {
    let components: [Int]

    init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }
        if let cutoff = text.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            text = String(text[..<cutoff])
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }

        var values: [Int] = []
        values.reserveCapacity(parts.count)
        for part in parts {
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(part)
            else { return nil }
            values.append(value)
        }
        components = values
    }

    /// "v1.1.0" → "1.1.0"; used when showing the version in Settings.
    var displayString: String {
        components.map { String($0) }.joined(separator: ".")
    }

    static func < (lhs: VersionNumber, rhs: VersionNumber) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

/// Manual update check against the public GitHub Releases API.
///
/// The app stays network-free until the user presses "检查更新"; this class is
/// the only code that talks to GitHub. It never downloads or installs a
/// release: a newer version only produces a link to the GitHub release page,
/// where the user copies the install command as usual.
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate(latest: String)
        case updateAvailable(latest: String, pageURL: URL)
        case failed(message: String)
    }

    static let repository = "kaiwenyao/anypaste"
    static let releasesAPIURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    static let latestReleasePageURL = URL(string: "https://github.com/\(repository)/releases/latest")!
    static let installCommand =
        "curl -fL --proto '=https' --proto-redir '=https'"
        + " -o install-anypaste-macos.sh"
        + " https://github.com/\(repository)/releases/latest/download/install-anypaste-macos.sh"
        + " && bash install-anypaste-macos.sh"

    @Published private(set) var phase: Phase = .idle

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    private init() {}

    var isChecking: Bool {
        if case .checking = phase { return true }
        return false
    }

    func check() {
        guard !isChecking else { return }
        phase = .checking

        var request = URLRequest(
            url: Self.releasesAPIURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("AnyPaste/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")

        AppLog.info("检查更新:当前版本 \(AppInfo.version) (\(AppInfo.build))")
        Self.session.dataTask(with: request) { [weak self] data, response, error in
            let result = Self.evaluate(data: data, response: response, error: error)
            DispatchQueue.main.async {
                guard let self else { return }
                self.phase = result
                switch result {
                case .upToDate(let latest):
                    AppLog.info("检查更新:已是最新版本(GitHub 最新 \(latest))")
                case .updateAvailable(let latest, _):
                    AppLog.info("检查更新:发现新版本 \(latest)")
                case .failed(let message):
                    AppLog.error("检查更新失败:\(message)")
                case .idle, .checking:
                    break
                }
            }
        }.resume()
    }

    /// Pure comparison used by the UI and by the headless self-test. Returns
    /// `nil` when either version cannot be parsed.
    static func isNewer(latestTag: String, than current: String) -> Bool? {
        guard let latest = VersionNumber(latestTag),
              let currentVersion = VersionNumber(current)
        else { return nil }
        return latest > currentVersion
    }

    // MARK: - Response handling

    private static func evaluate(data: Data?, response: URLResponse?, error: Error?) -> Phase {
        if let error {
            return .failed(message: message(for: error))
        }
        guard let http = response as? HTTPURLResponse else {
            return .failed(message: "GitHub 没有返回有效的响应,请稍后重试。")
        }
        switch http.statusCode {
        case 200:
            break
        case 403, 429:
            return .failed(message: "GitHub 查询受限(可能触发频率限制),请稍后重试。")
        case 404:
            return .failed(message: "GitHub 上还没有可用的 Release。")
        default:
            return .failed(message: "检查更新失败(HTTP \(http.statusCode))。")
        }
        guard let data, !data.isEmpty else {
            return .failed(message: "GitHub 返回的内容为空,请稍后重试。")
        }

        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            return .failed(message: "无法解析 GitHub 返回的版本信息。")
        }

        let tag = release.tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let latest = VersionNumber(tag) else {
            return .failed(message: "无法识别最新版本号 \(tag)。")
        }
        guard let newer = isNewer(latestTag: tag, than: AppInfo.version) else {
            return .failed(message: "无法识别当前版本号 \(AppInfo.version)。")
        }
        if newer {
            return .updateAvailable(
                latest: latest.displayString,
                pageURL: releasePageURL(from: release.htmlURL)
            )
        }
        return .upToDate(latest: latest.displayString)
    }

    private static func message(for error: Error) -> String {
        guard let urlError = error as? URLError else {
            return "检查更新失败:\(error.localizedDescription)"
        }
        switch urlError.code {
        case .notConnectedToInternet:
            return "没有网络连接,请检查网络后重试。"
        case .timedOut:
            return "连接 GitHub 超时,请稍后重试。"
        case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed:
            return "无法连接 GitHub,请检查网络后重试。"
        default:
            return "检查更新失败:\(urlError.localizedDescription)"
        }
    }

    private static func releasePageURL(from raw: String?) -> URL {
        guard let raw,
              let url = URL(string: raw),
              url.scheme == "https",
              url.host == "github.com"
        else {
            return latestReleasePageURL
        }
        return url
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: String?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}
