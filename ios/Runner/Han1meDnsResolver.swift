import Foundation

enum Han1meDnsResolver {
    private static let lock = NSLock()
    private static var cache: [String: (addresses: [String], expiresAt: Date)] = [:]
    private static let cacheTtl: TimeInterval = 300

    static func resolve(hostname: String, settings: Han1meNetworkSettings) -> [String]? {
        if settings.useBuiltInHosts && !settings.useDoh && Han1meHttpStore.hanimeHosts.contains(hostname) {
            return Han1meHttpStore.builtInAddresses
        }
        guard let dohUrl = settings.dohUrl else { return nil }

        lock.lock()
        let cached = cache[hostname]
        lock.unlock()
        if let cached, cached.expiresAt > Date() { return cached.addresses }

        // DoH 不可达时返回 nil 走系统解析，不让 DoH 故障拖垮全部请求（与 Android/桌面端一致）。
        let ipv4 = (try? queryDoh(hostname: hostname, dohUrl: dohUrl, settings: settings, type: "A")) ?? []
        let ipv6 = (try? queryDoh(hostname: hostname, dohUrl: dohUrl, settings: settings, type: "AAAA")) ?? []
        guard !ipv4.isEmpty || !ipv6.isEmpty else { return nil }
        let addresses = ipv4 + ipv6

        lock.lock()
        cache[hostname] = (addresses, Date().addingTimeInterval(cacheTtl))
        lock.unlock()
        return addresses
    }

    private static func queryDoh(hostname: String, dohUrl: String, settings: Han1meNetworkSettings, type: String) throws -> [String] {
        guard let template = URL(string: dohUrl) else { throw DnsError.invalidUrl }
        let hostHeader = template.host ?? ""
        let pathBase = template.path.hasSuffix("/") ? String(template.path.dropLast()) : template.path
        let queryPath = pathBase.isEmpty ? "/dns-query" : pathBase
        let query = "name=\(hostname.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? hostname)&type=\(type)"

        let bootstrapTargets: [URL] = {
            if settings.bootstrapIps.isEmpty, let direct = URL(string: "\(template.scheme ?? "https")://\(hostHeader)\(queryPath)?\(query)") {
                return [direct]
            }
            return settings.bootstrapIps.compactMap { ip in
                let formatted = ip.contains(":") ? "[\(ip)]" : ip
                return URL(string: "\(template.scheme ?? "https")://\(formatted)\(queryPath)?\(query)")
            }
        }()

        var lastError: Error = DnsError.emptyAnswer
        for target in bootstrapTargets {
            do {
                var request = URLRequest(url: target)
                request.httpMethod = "GET"
                request.timeoutInterval = TimeInterval(settings.dohTimeoutSeconds)
                request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
                if !hostHeader.isEmpty { request.setValue(hostHeader, forHTTPHeaderField: "Host") }

                let (data, response) = try URLSession.shared.syncData(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                let ips = parseDnsJson(data, type: type)
                if !ips.isEmpty { return ips }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func parseDnsJson(_ data: Data, type: String) -> [String] {
        let wanted = type == "AAAA" ? 28 : 1
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let answers = json["Answer"] as? [[String: Any]]
        else { return [] }
        return answers.compactMap { answer in
            guard let recordType = answer["type"] as? Int, recordType == wanted, let value = answer["data"] as? String else { return nil }
            return value
        }
    }

    enum DnsError: LocalizedError {
        case invalidUrl
        case emptyAnswer

        var errorDescription: String? {
            switch self {
            case .invalidUrl: return "Invalid DoH URL"
            case .emptyAnswer: return "DoH returned no addresses"
            }
        }
    }
}

private extension URLSession {
    func syncData(for request: URLRequest) throws -> (Data, URLResponse) {
        var result: Result<(Data, URLResponse), Error>?
        let semaphore = DispatchSemaphore(value: 0)
        let task = dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else if let data, let response {
                result = .success((data, response))
            } else {
                result = .failure(Han1meDnsResolver.DnsError.emptyAnswer)
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        switch result {
        case .success(let value): return value
        case .failure(let error): throw error
        case .none: throw Han1meDnsResolver.DnsError.emptyAnswer
        }
    }
}
