import Darwin
import Foundation
import Network
import SystemConfiguration

/// IPv4 of the Wi-Fi or Ethernet interface that owns the default route.
/// A VPN tunnel is not the LAN interface: when the global route is a tunnel,
/// the hardware interface that still has a default route is used instead.
final class IPService {
    var onIP: ((String) -> Void)?
    var onUnreachable: (() -> Void)?

    private let queue = DispatchQueue(label: "local.myip.widget.lan")
    private let monitor = NWPathMonitor()
    private var timer: DispatchSourceTimer?
    private var store: SCDynamicStore?
    private var started = false

    func start() {
        guard !started else { return }
        started = true

        monitor.pathUpdateHandler = { [weak self] _ in
            self?.refresh()
        }
        monitor.start(queue: queue)

        installStoreNotifications()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 20, repeating: 20, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            self?.refresh()
        }
        timer.resume()
        self.timer = timer

        refresh()
    }

    /// Reads the current LAN address. Safe to call from any queue.
    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            let address = Self.primaryLANIPv4()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let address {
                    self.onIP?(address)
                } else {
                    self.onUnreachable?()
                }
            }
        }
    }

    private func installStoreNotifications() {
        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        guard let store = SCDynamicStoreCreate(nil, "local.myip.widget" as CFString, { _, _, info in
            guard let info else { return }
            Unmanaged<IPService>.fromOpaque(info).takeUnretainedValue().refresh()
        }, &context) else {
            return
        }
        let patterns = [
            "State:/Network/Global/IPv4",
            "State:/Network/Interface/.*/IPv4",
            "State:/Network/Interface/.*/Link",
        ] as CFArray
        SCDynamicStoreSetNotificationKeys(store, nil, patterns)
        SCDynamicStoreSetDispatchQueue(store, queue)
        self.store = store
    }

    /// Wi-Fi or Ethernet IPv4 for the default route, or nil when none is assigned.
    static func primaryLANIPv4() -> String? {
        let hardware = hardwareInterfaces()
        let routes = defaultRoutes().filter { hardware[$0.name] != nil }
        if let route = routes.first(where: { !$0.scoped }) ?? routes.first,
           let address = ipv4Address(on: route.name) {
            return address
        }
        let ranked = hardware.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value == .wifi }
            return lhs.key < rhs.key
        }
        for entry in ranked {
            if let address = ipv4Address(on: entry.key) {
                return address
            }
        }
        return nil
    }

    private enum Kind { case wifi, ethernet }

    private static func hardwareInterfaces() -> [String: Kind] {
        let list = SCNetworkInterfaceCopyAll()
        var found: [String: Kind] = [:]
        let count = CFArrayGetCount(list)
        for index in 0..<count {
            guard let pointer = CFArrayGetValueAtIndex(list, index) else { continue }
            let iface = Unmanaged<SCNetworkInterface>.fromOpaque(pointer).takeUnretainedValue()
            guard let bsd = SCNetworkInterfaceGetBSDName(iface) as String?,
                  let type = SCNetworkInterfaceGetInterfaceType(iface) as String? else {
                continue
            }
            if type == (kSCNetworkInterfaceTypeIEEE80211 as String) {
                found[bsd] = .wifi
            } else if type == (kSCNetworkInterfaceTypeEthernet as String) {
                found[bsd] = .ethernet
            }
        }
        return found
    }

    private struct DefaultRoute {
        let name: String
        let scoped: Bool
    }

    /// IPv4 routes whose destination is 0.0.0.0/0.
    private static func defaultRoutes() -> [DefaultRoute] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_DUMP, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return [] }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: length, alignment: MemoryLayout<rt_msghdr>.alignment)
        defer { buffer.deallocate() }
        guard sysctl(&mib, 6, buffer, &length, nil, 0) == 0 else { return [] }

        var routes: [DefaultRoute] = []
        var offset = 0
        let headerSize = MemoryLayout<rt_msghdr>.stride
        while offset + headerSize <= length {
            let header = buffer.loadUnaligned(fromByteOffset: offset, as: rt_msghdr.self)
            let messageLength = Int(header.rtm_msglen)
            if messageLength < headerSize || offset + messageLength > length { break }
            if header.rtm_version == RTM_VERSION, (header.rtm_flags & RTF_UP) != 0 {
                let start = buffer.advanced(by: offset + headerSize)
                let end = buffer.advanced(by: offset + messageLength)
                if isDefaultDestination(start, end: end, addrs: header.rtm_addrs),
                   let name = interfaceName(index: UInt32(header.rtm_index)) {
                    routes.append(DefaultRoute(
                        name: name,
                        scoped: (header.rtm_flags & RTF_IFSCOPE) != 0
                    ))
                }
            }
            offset += messageLength
        }
        return routes
    }

    private static func isDefaultDestination(_ start: UnsafeRawPointer, end: UnsafeRawPointer, addrs: Int32) -> Bool {
        var pointer = start
        var bit: Int32 = RTA_DST
        while bit <= RTA_BRD {
            if (addrs & bit) != 0 {
                if pointer.advanced(by: 2) > end { return false }
                let length = Int(pointer.load(as: UInt8.self))
                let advance = length > 0 ? (length + 3) & ~3 : 4
                if pointer.advanced(by: advance) > end { return false }
                if bit == RTA_DST {
                    let family = pointer.advanced(by: 1).load(as: UInt8.self)
                    if family != UInt8(AF_INET) || length < MemoryLayout<sockaddr_in>.size {
                        return false
                    }
                    let address = pointer.advanced(by: MemoryLayout<sockaddr_in>.offset(of: \sockaddr_in.sin_addr)! )
                        .load(as: in_addr.self)
                    if address.s_addr != 0 { return false }
                }
                pointer = pointer.advanced(by: advance)
            }
            bit <<= 1
        }
        return true
    }

    private static func interfaceName(index: UInt32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        guard if_indextoname(index, &buffer) != nil else { return nil }
        let name = String(cString: buffer)
        return name.isEmpty ? nil : name
    }

    /// First useful IPv4 on `name`. Link-local is used only when nothing else is assigned.
    private static func ipv4Address(on name: String) -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return nil }
        defer { freeifaddrs(head) }
        var linkLocal: String?
        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let current = cursor {
            let entry = current.pointee
            cursor = entry.ifa_next
            guard let sa = entry.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            guard String(cString: entry.ifa_name) == name else { continue }
            let flags = Int32(entry.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            var address = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &address, &text, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            let ip = String(cString: text)
            guard isUsableIPv4(ip) else { continue }
            if ip.hasPrefix("169.254.") {
                linkLocal = ip
                continue
            }
            return ip
        }
        return linkLocal
    }

    private static func isUsableIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, value != "0.0.0.0", value != "255.255.255.255" else { return false }
        return parts.allSatisfy { part in
            guard let number = Int(part), (0...255).contains(number), String(number) == part else { return false }
            return true
        }
    }
}

/// Public IPv4. ipify first, then ifconfig.me, then Cloudflare trace.
final class PublicIPService {
    var onIP: ((String) -> Void)?
    var onUnreachable: (() -> Void)?

    private struct Endpoint {
        enum Kind { case plain, trace }
        let url: URL
        let kind: Kind
    }

    private let endpoints: [Endpoint] = [
        Endpoint(url: URL(string: "https://api.ipify.org")!, kind: .plain),
        Endpoint(url: URL(string: "https://ifconfig.me/ip")!, kind: .plain),
        Endpoint(url: URL(string: "https://1.1.1.1/cdn-cgi/trace")!, kind: .trace),
    ]

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "local.myip.widget.wan")
    private let session: URLSession
    private var timer: DispatchSourceTimer?
    private var task: URLSessionDataTask?
    private var generation = 0
    private var started = false

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 8
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = false
        config.urlCache = nil
        session = URLSession(configuration: config)
    }

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            if path.status == .satisfied {
                self.refresh()
            } else {
                self.generation += 1
                self.task?.cancel()
                self.task = nil
                DispatchQueue.main.async { [weak self] in
                    self?.onUnreachable?()
                }
            }
        }
        monitor.start(queue: queue)

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 25, repeating: 25, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in
            self?.refresh()
        }
        timer.resume()
        self.timer = timer
        refresh()
    }

    func refresh() {
        queue.async { [weak self] in
            self?.beginFetch()
        }
    }

    private func beginFetch() {
        generation += 1
        let gen = generation
        task?.cancel()
        task = nil
        fetch(index: 0, generation: gen)
    }

    private func fetch(index: Int, generation gen: Int) {
        guard index < endpoints.count else {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == gen else { return }
                self.onUnreachable?()
            }
            return
        }
        let endpoint = endpoints[index]
        var request = URLRequest(
            url: endpoint.url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 6
        )
        request.setValue("curl/8.4.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain, */*;q=0.1", forHTTPHeaderField: "Accept")
        let kind = endpoint.kind
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            let ip = PublicIPService.parse(data: data, response: response, error: error, kind: kind)
            self?.queue.async {
                guard let self, self.generation == gen else { return }
                if let ip {
                    DispatchQueue.main.async { self.onIP?(ip) }
                } else {
                    self.fetch(index: index + 1, generation: gen)
                }
            }
        }
        self.task = task
        task.resume()
    }

    private static func parse(data: Data?, response: URLResponse?, error: Error?, kind: Endpoint.Kind) -> String? {
        if error != nil { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return nil
        }
        guard let data, !data.isEmpty, data.count < 8192,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        switch kind {
        case .plain:
            return ipv4(in: text)
        case .trace:
            for line in text.split(whereSeparator: \.isNewline) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("ip=") else { continue }
                return ipv4(in: String(trimmed.dropFirst(3)))
            }
            return nil
        }
    }

    private static func ipv4(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if isIPv4(trimmed) { return trimmed }
        for token in trimmed.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == ";" }) {
            let candidate = String(token).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if isIPv4(candidate) { return candidate }
        }
        return nil
    }

    private static func isIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let number = Int(part), (0...255).contains(number), String(number) == part else { return false }
            return true
        }
    }
}
