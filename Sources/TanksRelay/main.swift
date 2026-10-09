import Foundation
import TanksNet
import TanksRelayCore

let environment = ProcessInfo.processInfo.environment
let port = environment["PORT"].flatMap(Int.init) ?? 8080
let roomTTL = environment["ROOM_TTL"].flatMap(Double.init) ?? RelayLimits.defaultRoomTTL

let server = RelayServer(roomTTL: roomTTL)
let boundPort = try server.start(host: "0.0.0.0", port: port)
print("TanksRelay listening on ws://0.0.0.0:\(boundPort)/ws (protocol \(TanksNet.protocolVersion))")
try server.waitUntilClosed()
