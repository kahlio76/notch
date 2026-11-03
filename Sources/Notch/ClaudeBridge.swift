import Foundation
import NotchCore

/// Listens on ~/.notch/notch.sock for notch-hook. The directory and socket are private
/// to this user, and a connection held open by the hook is a request awaiting an answer.
final class ClaudeBridge {
    private let store: NotchStore
    private let path = Config.directory + "/notch.sock"
    private var listener: Int32 = -1

    init(store: NotchStore) { self.store = store }

    private func address() -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8)) }
        return address
    }

    private func withSockaddr<T>(_ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        var value = address()
        return withUnsafePointer(to: &value) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }

    /// False if another running copy already answers on the socket.
    func start() -> Bool {
        try? FileManager.default.createDirectory(atPath: Config.directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        chmod(Config.directory, 0o700)
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(probe) }
        if withSockaddr({ connect(probe, $0, $1) }) == 0 { return false }

        unlink(path)
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0, withSockaddr({ bind(listener, $0, $1) }) == 0 else { return true }
        chmod(path, 0o600)
        listen(listener, 32)
        Thread.detachNewThread { [weak self] in self?.acceptLoop() }
        return true
    }

    private func acceptLoop() {
        while true {
            let fd = accept(listener, nil, nil)
            if fd < 0 { continue }
            Thread.detachNewThread { [weak self] in self?.serve(fd) }
        }
    }

    private func serve(_ fd: Int32) {
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var line = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        while line.last != 0x0A {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            line.append(contentsOf: chunk[0..<n])
        }
        guard line.last == 0x0A, let event = ClaudeEvent(json: line) else {
            close(fd)
            return
        }
        close(fd)
        DispatchQueue.main.async { self.store.handle(event) }
    }
}
