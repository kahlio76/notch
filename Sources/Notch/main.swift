import AppKit

signal(SIGPIPE, SIG_IGN)

let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--snapshot"), arguments.count > flag + 1 {
    MainActor.assumeIsolated { Snapshot.run(to: arguments[flag + 1]) }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
