// Drives the bundled wireguard-go binary (official upstream source, built
// from https://github.com/WireGuard/wireguard-go - see
// macos/Runner/Resources/wireguard-go/) directly, without Apple's
// NetworkExtension framework. That framework is what forces a paid Apple
// Developer Program membership and a separate Packet Tunnel Provider
// extension target - this app isn't sandboxed (see the Runner
// entitlements files) and isn't distributed via the Mac App Store, so it
// can create the utun interface and configure it directly instead, the
// same way `wg-quick` + `wireguard-go` do when installed via Homebrew.
//
// Protocol: WireGuard's cross-platform userspace UAPI (a small text
// protocol over a Unix socket at /var/run/wireguard/<ifname>.sock) -
// see https://www.wireguard.com/xplatform/. This talks to it directly
// rather than shelling out to the `wg` CLI, which is C (not Go) and so
// isn't something this session could cross-compile from Linux the way
// wireguard-go itself was.
//
// UNVERIFIED: written from the documented protocol and wireguard-go's
// known behavior, but never compiled or run - there is no macOS toolchain
// available in the sandbox this was written in. Expect a debugging pass
// on real hardware, most likely around: the exact interface-name log line
// wireguard-go prints (parsed below to find the UAPI socket path), and
// whether the elevated-process plumbing behaves as expected.
import Cocoa
import FlutterMacOS
import Darwin

private let channelName = "archangel/wireguard_macos"

enum WGMacError: Error {
    case message(String)
}

class WireGuardMacOS: NSObject {
    private var process: Process?
    private var interfaceName: String?
    private var uapiSocketFD: Int32 = -1

    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
        let instance = WireGuardMacOS()
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "connect":
                guard let args = call.arguments as? [String: Any],
                      let config = args["config"] as? String
                else {
                    result(FlutterError(code: "bad_args", message: "config is required", details: nil))
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try instance.connect(config: config)
                        DispatchQueue.main.async { result(nil) }
                    } catch WGMacError.message(let msg) {
                        DispatchQueue.main.async { result(FlutterError(code: "connect_failed", message: msg, details: nil)) }
                    } catch {
                        DispatchQueue.main.async { result(FlutterError(code: "connect_failed", message: "\(error)", details: nil)) }
                    }
                }
            case "disconnect":
                instance.disconnect()
                result(nil)
            case "status":
                result(instance.interfaceName != nil ? "connected" : "disconnected")
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // MARK: - Connect

    private func connect(config: String) throws {
        disconnect() // idempotent - clears any previous session first

        let parsed = try WGConfig.parse(config)
        let binaryPath = try bundledWireguardGoPath()

        // wireguard-go logs the real interface name it picked to stderr as
        // it starts (asking for a bare "utun" lets macOS/the kernel assign
        // the next free number, avoiding collisions with other tunnels).
        // We read that from a log file rather than piping stderr directly,
        // since the process itself needs to be launched elevated (below)
        // and elevated processes' pipes are awkward to read from directly.
        let logPath = NSTemporaryDirectory() + "archangel-wireguard-go.log"
        FileManager.default.createFile(atPath: logPath, contents: nil)

        // Foreground (not -f/daemonize) so `process` tracks its lifetime
        // and disconnect() can just terminate it. Needs root to create the
        // utun device at all - osascript's "with administrator privileges"
        // gives the native macOS password prompt, no separate helper tool
        // or Developer Program entitlement required.
        let launchCommand = "'\(binaryPath)' utun > '\(logPath)' 2>&1 &\necho $! > '\(logPath).pid'"
        let escaped = launchCommand.replacingOccurrences(of: "\"", with: "\\\"")
        let osascript = """
        do shell script "\(escaped)" with administrator privileges
        """

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", osascript]
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw WGMacError.message("Could not start wireguard-go (admin authorization declined or failed).")
        }
        self.process = task

        // Give wireguard-go a moment to create the interface and print its
        // name, then parse the log for it.
        let ifname = try waitForInterfaceName(logPath: logPath, timeout: 5.0)
        self.interfaceName = ifname

        try configureViaUAPI(ifname: ifname, config: parsed)
        try bringUpInterface(ifname: ifname, address: parsed.address)
    }

    private func waitForInterfaceName(logPath: String, timeout: TimeInterval) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        // wireguard-go's startup log includes a line like:
        //   "(utun7) Starting wireguard-go version 0.0.20230223"
        // — this regex is the part most likely to need adjusting once this
        // runs against a real build's actual log wording.
        let pattern = try! NSRegularExpression(pattern: "\\((utun[0-9]+)\\)")

        while Date() < deadline {
            if let contents = try? String(contentsOfFile: logPath, encoding: .utf8) {
                if let match = pattern.firstMatch(in: contents, range: NSRange(contents.startIndex..., in: contents)),
                   let range = Range(match.range(at: 1), in: contents) {
                    return String(contents[range])
                }
                if contents.lowercased().contains("error") || contents.lowercased().contains("denied") {
                    throw WGMacError.message("wireguard-go failed to start: \(contents)")
                }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw WGMacError.message("Timed out waiting for wireguard-go to create the tunnel interface.")
    }

    // MARK: - UAPI configuration

    private func configureViaUAPI(ifname: String, config: WGConfig) throws {
        let socketPath = "/var/run/wireguard/\(ifname).sock"
        let deadline = Date().addingTimeInterval(3.0)
        while !FileManager.default.fileExists(atPath: socketPath) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw WGMacError.message("Could not create UAPI socket") }
        defer { self.uapiSocketFD = fd }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        withUnsafeMutableBytes(of: &addr.sun_path) { ptr in
            for (i, b) in pathBytes.enumerated() where i < ptr.count - 1 {
                ptr[i] = Int8(bitPattern: b)
            }
        }
        let size = MemoryLayout<sockaddr_un>.size
        let connectResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(size))
            }
        }
        guard connectResult == 0 else {
            throw WGMacError.message("Could not connect to wireguard-go's UAPI socket at \(socketPath)")
        }

        var message = "set=1\n"
        message += "private_key=\(try WGConfig.base64KeyToHex(config.privateKey))\n"
        message += "replace_peers=true\n"
        message += "public_key=\(try WGConfig.base64KeyToHex(config.peerPublicKey))\n"
        message += "endpoint=\(try WGConfig.resolveEndpoint(config.peerEndpoint))\n"
        if let keepalive = config.persistentKeepalive {
            message += "persistent_keepalive_interval=\(keepalive)\n"
        }
        message += "replace_allowed_ips=true\n"
        for cidr in config.allowedIps {
            message += "allowed_ip=\(cidr)\n"
        }
        message += "\n"

        let sent = message.withCString { write(fd, $0, strlen($0)) }
        guard sent > 0 else { throw WGMacError.message("Failed writing UAPI config") }

        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(fd, &buf, buf.count)
        let response = n > 0 ? String(decoding: buf[0..<n], as: UTF8.self) : ""
        if !response.contains("errno=0") && !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw WGMacError.message("wireguard-go rejected the config: \(response)")
        }
    }

    // MARK: - Interface addressing / routing

    private func bringUpInterface(ifname: String, address: String) throws {
        // address is CIDR form, e.g. "10.8.0.5/32" - ifconfig wants the
        // parts split out.
        let parts = address.split(separator: "/")
        guard parts.count == 2, let prefixLen = Int(parts[1]) else {
            throw WGMacError.message("Invalid interface address: \(address)")
        }
        let ip = String(parts[0])
        let mask = WGConfig.prefixLengthToMask(prefixLen)

        let cmd = "ifconfig \(ifname) inet \(ip) \(ip) netmask \(mask) up"
        let escaped = cmd.replacingOccurrences(of: "\"", with: "\\\"")
        let osascript = "do shell script \"\(escaped)\" with administrator privileges"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", osascript]
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw WGMacError.message("Failed to configure the tunnel interface address (ifconfig).")
        }
        // Routing for AllowedIPs beyond the interface's own /32 is
        // intentionally left to a follow-up - most configs use a narrow
        // AllowedIPs (this server's own subnet) rather than full-tunnel
        // 0.0.0.0/0, and getting split-tunnel routing right on macOS
        // without clobbering the default route needs more care than this
        // first pass covers.
    }

    // MARK: - Disconnect

    private func disconnect() {
        if uapiSocketFD >= 0 {
            close(uapiSocketFD)
            uapiSocketFD = -1
        }
        process?.terminate()
        process = nil
        interfaceName = nil
    }

    // MARK: - Bundled binary

    private func bundledWireguardGoPath() throws -> String {
        #if arch(arm64)
        let name = "wireguard-go-arm64"
        #else
        let name = "wireguard-go-amd64"
        #endif
        guard let path = Bundle.main.path(forResource: name, ofType: nil, inDirectory: "wireguard-go") else {
            throw WGMacError.message("Bundled \(name) not found in app Resources - see WIREGUARD.md for the Xcode step needed to add it to Copy Bundle Resources.")
        }
        return path
    }
}

/// Parses the same wg-quick-style config TunnelConfig.toWgQuickConfig()
/// produces on the Dart side, and the small key/endpoint helpers the UAPI
/// protocol needs that the C `wg` CLI would normally handle.
struct WGConfig {
    let privateKey: String
    let address: String
    let peerPublicKey: String
    let peerEndpoint: String
    let allowedIps: [String]
    let persistentKeepalive: Int?

    static func parse(_ text: String) throws -> WGConfig {
        var privateKey: String?, address: String?, publicKey: String?, endpoint: String?
        var allowedIps: [String] = []
        var keepalive: Int?
        var section = ""

        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast()).lowercased()
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[line.startIndex..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)

            if section == "interface" {
                if key == "privatekey" { privateKey = value }
                if key == "address" { address = value }
            } else if section == "peer" {
                if key == "publickey" { publicKey = value }
                if key == "endpoint" { endpoint = value }
                if key == "allowedips" { allowedIps = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                if key == "persistentkeepalive" { keepalive = Int(value) }
            }
        }

        guard let pk = privateKey, let addr = address, let pubk = publicKey, let ep = endpoint else {
            throw WGMacError.message("Incomplete WireGuard config")
        }
        return WGConfig(privateKey: pk, address: addr, peerPublicKey: pubk, peerEndpoint: ep,
                         allowedIps: allowedIps.isEmpty ? ["0.0.0.0/0"] : allowedIps, persistentKeepalive: keepalive)
    }

    /// WireGuard keys are base64 in .conf files; the UAPI wants lowercase hex.
    static func base64KeyToHex(_ base64Key: String) throws -> String {
        guard let data = Data(base64Encoded: base64Key), data.count == 32 else {
            throw WGMacError.message("Invalid WireGuard key: \(base64Key)")
        }
        return data.map { String(format: "%02x", $0) }.joined()
    }

    /// The UAPI's `endpoint=` wants "ip:port". archangeld's own pairing
    /// config (and every config this app generates) already uses the
    /// server's tunnel IP literally rather than a hostname, so this only
    /// validates the shape rather than performing real DNS resolution -
    /// if a hostname endpoint is ever needed, resolve it before it reaches
    /// here rather than adding getaddrinfo plumbing to this method.
    static func resolveEndpoint(_ endpoint: String) throws -> String {
        guard let lastColon = endpoint.lastIndex(of: ":"),
              let port = Int(endpoint[endpoint.index(after: lastColon)...]),
              port > 0 && port <= 65535
        else {
            throw WGMacError.message("Invalid endpoint (expected ip:port): \(endpoint)")
        }
        return endpoint
    }

    static func prefixLengthToMask(_ prefixLen: Int) -> String {
        let mask: UInt32 = prefixLen == 0 ? 0 : ~UInt32(0) << (32 - prefixLen)
        return [24, 16, 8, 0].map { String((mask >> $0) & 0xff) }.joined(separator: ".")
    }
}
