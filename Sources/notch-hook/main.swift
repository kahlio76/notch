// Claude Code runs this for each hook event. It forwards the payload to Notch.app and,
// for a permission request, prints the decision made in the notch. Anything going wrong
// (app not running, no answer in time) exits 0 with no output, so Claude Code falls back
// to its normal prompt. This must never decide anything on its own.
import Foundation

signal(SIGPIPE, SIG_IGN)
let answerTimeoutSeconds = 110

var payload = FileHandle.standardInput.readDataToEndOfFile()
let event = (try? JSONSerialization.jsonObject(with: payload) as? [String: Any])?["hook_event_name"] as? String
// A raw newline can only be JSON whitespace, so this keeps the payload to one framed line.
payload = Data(payload.map { $0 == 0x0A ? 0x20 : $0 }) + [0x0A]

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { exit(0) }

var address = sockaddr_un()
address.sun_family = sa_family_t(AF_UNIX)
let path = NSHomeDirectory() + "/.notch/notch.sock"
guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { exit(0) }
withUnsafeMutableBytes(of: &address.sun_path) { buffer in
    buffer.copyBytes(from: Array(path.utf8))
}
let connected = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard connected == 0 else { exit(0) }

let wrote = payload.withUnsafeBytes { buffer -> Bool in
    var offset = 0
    while offset < buffer.count {
        let n = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
        if n <= 0 { return false }
        offset += n
    }
    return true
}
guard wrote, event == "PermissionRequest" else { exit(0) }

var timeout = timeval(tv_sec: answerTimeoutSeconds, tv_usec: 0)
setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
var answer = Data()
var chunk = [UInt8](repeating: 0, count: 4096)
while true {
    let n = read(fd, &chunk, chunk.count)
    if n <= 0 { break }
    answer.append(contentsOf: chunk[0..<n])
}
if answer.last == 0x0A { FileHandle.standardOutput.write(answer) }
exit(0)
