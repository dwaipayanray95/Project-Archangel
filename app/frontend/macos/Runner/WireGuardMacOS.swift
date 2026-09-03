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
// Status: the PREVIOUS version of this file was compiled and run on real
// hardware (no macOS toolchain exists in the sandbox this file is edited
// from, so nothing here is compiled by the person/agent making these
// changes - real building and testing happens only on the actual Mac).
// That run confirmed interface creation and UAPI configuration both work
// (a utun interface came up with the expected address) and surfaced two
// real bugs, fixed below but NOT YET recompiled or retested:
//   1. wireguard-go daemonizes (double-forks into the background) by
//      default, detaching from both the log redirection and the PID our
//      shell's `$!` captured - WG_PROCESS_FOREGROUND=1 below stops that,
//      and the interface name is now computed ourselves via `ifconfig -l`
//      rather than parsed from a log line that daemonizing meant we'd
//      often never actually see.
//   2. disconnect() was tracking and terminating the *osascript* wrapper
//      process, not the actual (elevated, root-owned) wireguard-go
//      process it launched - every connect attempt leaked a permanent
//      root process. Fixed to kill the real PID (plus an exact-match
//      pkill fallback) via the same elevated-privileges path.
// A SECOND real-hardware run (after fixing the above) got further - the
// socket now reliably appears - but failed to connect() to it: wireguard-go
// (root) creates /var/run/wireguard/ and the socket itself root-owned, and
// this process's own connect() call runs as the logged-in user, not root.
// Fixed with relaxUapiSocketPermissions() (an elevated chmod) right after
// the socket appears, before connecting to it. Not yet retested.
import Cocoa
import FlutterMacOS
import Darwin

private let channelName = "archangel/wireguard_macos"

enum WGMacError: Error {
    case message(String)
}

class WireGuardMacOS: NSObject {
    private var wgPID: Int32?
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

        // Pick the interface name ourselves (rather than passing a bare
        // "utun" and parsing wireguard-go's log for whatever it picked) -
        // real-hardware testing showed wireguard-go's default behavior is
        // to daemonize (double-fork into the background), which detaches
        // it from both our log redirection and the PID `$!` would have
        // captured. WG_PROCESS_FOREGROUND=1 below stops the daemonizing,
        // but computing the name ourselves removes the log-parsing race
        // entirely regardless.
        let ifname = try nextFreeUtunName()

        let logPath = NSTemporaryDirectory() + "archangel-wireguard-go.log"
        let pidPath = logPath + ".pid"
        FileManager.default.createFile(atPath: logPath, contents: nil)

        // Needs root to create the utun device at all - osascript's "with
        // administrator privileges" gives the native macOS password
        // prompt, no separate helper tool or Developer Program entitlement
        // required.
        let launchCommand = "WG_PROCESS_FOREGROUND=1 '\(binaryPath)' \(ifname) > '\(logPath)' 2>&1 & echo $! > '\(pidPath)'"
        let escaped = launchCommand.replacingOccurrences(of: "\"", with: "\\\"")
        let osascript = "do shell script \"\(escaped)\" with administrator privileges"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", osascript]
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw WGMacError.message("Could not start wireguard-go (admin authorization declined or failed).")
        }

        self.interfaceName = ifname
        self.wgPID = try? readPID(pidPath: pidPath)

        try waitForUapiSocket(ifname: ifname, logPath: logPath, timeout: 5.0)
        // wireguard-go (running as root) creates both /var/run/wireguard/
        // and the socket itself as root-owned - our own connect() call
        // below runs as the logged-in user, not root, so without this it
        // fails with a plain "could not connect" (a permission failure,
        // not a missing-file one; the socket already exists by this
        // point). Single elevated call, reusing the same admin-privileges
        // path everything else here already needs.
        try relaxUapiSocketPermissions(ifname: ifname)
        try configureViaUAPI(ifname: ifname, config: parsed)
        try bringUpInterface(ifname: ifname, address: parsed.address)
    }

    private func relaxUapiSocketPermissions(ifname: String) throws {
        let cmd = "chmod 755 /var/run/wireguard && chmod 666 /var/run/wireguard/\(ifname).sock"
        let escaped = cmd.replacingOccurrences(of: "\"", with: "\\\"")
        let osascript = "do shell script \"\(escaped)\" with administrator privileges"
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", osascript]
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw WGMacError.message("Could not relax permissions on wireguard-go's UAPI socket.")
        }
    }

    /// Lists currently-existing utunN interfaces via `ifconfig -l` (a plain
    /// unprivileged listing) and returns the next free number - avoids
    /// ever colliding with another tunnel already on this Mac.
    private func nextFreeUtunName() throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        task.arguments = ["-l"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let names = String(decoding: data, as: UTF8.self).split(separator: " ")
        let usedNumbers = names.compactMap { name -> Int? in
            guard name.hasPrefix("utun") else { return nil }
            return Int(name.dropFirst(4))
        }
        return "utun\((usedNumbers.max() ?? -1) + 1)"
    }

    private func readPID(pidPath: String) throws -> Int32 {
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            if let s = try? String(contentsOfFile: pidPath, encoding: .utf8),
               let pid = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return pid
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw WGMacError.message("Could not read wireguard-go's PID")
    }

    private func waitForUapiSocket(ifname: String, logPath: String, timeout: TimeInterval) throws {
        let socketPath = "/var/run/wireguard/\(ifname).sock"
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: socketPath) { return }
            if let contents = try? String(contentsOfFile: logPath, encoding: .utf8),
               contents.lowercased().contains("error") || contents.lowercased().contains("denied") {
                throw WGMacError.message("wireguard-go failed to start: \(contents)")
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        let logContents = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? "(no log output)"
        throw WGMacError.message("Timed out waiting for wireguard-go's UAPI socket. Log: \(logContents)")
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
        // Tracked from creation so disconnect() can always close it, but
        // closed and untracked again below on any failure - configuration
        // can fail well after this point (connect, write, or a rejected
        // config), and a socket that never got a working UAPI session on
        // it has nothing worth keeping open until the next connect/
        // disconnect call happens to clean it up.
        self.uapiSocketFD = fd
        func fail(_ message: String) -> WGMacError {
            close(fd)
            self.uapiSocketFD = -1
            return .message(message)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        withUnsafeMutableBytes(of: &addr.sun_path) { ptr in
            // withUnsafeMutableBytes exposes raw UInt8 regardless of
            // sun_path's own element type (C `char`/Int8) - assign the
            // utf8 bytes (already UInt8) directly, no conversion needed.
            for (i, b) in pathBytes.enumerated() where i < ptr.count - 1 {
                ptr[i] = b
            }
        }
        let size = MemoryLayout<sockaddr_un>.size
        let connectResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(size))
            }
        }
        guard connectResult == 0 else {
            throw fail("Could not connect to wireguard-go's UAPI socket at \(socketPath)")
        }

        let message: String
        do {
            var m = "set=1\n"
            m += "private_key=\(try WGConfig.base64KeyToHex(config.privateKey))\n"
            m += "replace_peers=true\n"
            m += "public_key=\(try WGConfig.base64KeyToHex(config.peerPublicKey))\n"
            m += "endpoint=\(try WGConfig.resolveEndpoint(config.peerEndpoint))\n"
            if let keepalive = config.persistentKeepalive {
                m += "persistent_keepalive_interval=\(keepalive)\n"
            }
            m += "replace_allowed_ips=true\n"
            for cidr in config.allowedIps {
                m += "allowed_ip=\(cidr)\n"
            }
            m += "\n"
            message = m
        } catch WGMacError.message(let msg) {
            throw fail(msg)
        }

        let sent = message.withCString { write(fd, $0, strlen($0)) }
        guard sent > 0 else { throw fail("Failed writing UAPI config") }

        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(fd, &buf, buf.count)
        let response = n > 0 ? String(decoding: buf[0..<n], as: UTF8.self) : ""
        if !response.contains("errno=0") && !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw fail("wireguard-go rejected the config: \(response)")
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

        // wireguard-go runs as root (launched via administrator
        // privileges), so killing it needs the same elevation - a plain
        // Process.terminate() from this unprivileged process can't touch
        // it. Real-hardware testing surfaced this the hard way: the
        // previous version tracked and terminated the *osascript* wrapper
        // instead (which had already exited), leaking a root wireguard-go
        // process on every single connect attempt. Kill by PID and by an
        // exact-match pkill together (single admin prompt) so a stale or
        // missing PID still gets cleaned up.
        if let pid = wgPID, let binaryPath = try? bundledWireguardGoPath(), let ifname = interfaceName {
            let cmd = "kill \(pid) 2>/dev/null; pkill -f '\(binaryPath) \(ifname)' 2>/dev/null; true"
            let escaped = cmd.replacingOccurrences(of: "\"", with: "\\\"")
            let osascript = "do shell script \"\(escaped)\" with administrator privileges"
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            task.arguments = ["-e", osascript]
            try? task.run()
            task.waitUntilExit()
        }

        wgPID = nil
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
