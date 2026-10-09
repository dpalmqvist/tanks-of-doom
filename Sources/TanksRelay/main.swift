#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import Dispatch
import Foundation
import TanksNet
import TanksRelayCore

// Line-buffered stdout, so logs show up promptly when redirected to a file or a container log.
setvbuf(stdout, nil, _IOLBF, 0)

// Exit promptly on SIGTERM (container stop) and SIGINT. The main thread is blocked waiting on the
// server, so the handlers run on a background queue.
let signalSources = [SIGTERM, SIGINT].map { signalNumber -> DispatchSourceSignal in
    signal(signalNumber, SIG_IGN)   // let the dispatch source see it instead of the default handler
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
    source.setEventHandler {
        print("TanksRelay stopping (signal \(signalNumber))")
        exit(0)
    }
    source.resume()
    return source
}

let environment = ProcessInfo.processInfo.environment
let port = environment["PORT"].flatMap(Int.init) ?? 8080
let roomTTL = environment["ROOM_TTL"].flatMap(Double.init) ?? RelayLimits.defaultRoomTTL

let server = RelayServer(roomTTL: roomTTL)
let boundPort = try server.start(host: "0.0.0.0", port: port)
print("TanksRelay listening on ws://0.0.0.0:\(boundPort)/ws (protocol \(TanksNet.protocolVersion))")
try server.waitUntilClosed()
withExtendedLifetime(signalSources) {}
