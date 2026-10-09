import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket
import TanksNet

/// The relay's WebSocket server: accepts game connections on `/ws` and lets `RelayCore` decide what
/// happens to every frame. It runs on a single event loop, so its state needs no locks.
public final class RelayServer: @unchecked Sendable {
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private let roomTTL: Double
    private var core = RelayCore<ObjectIdentifier>()
    private var channels: [ObjectIdentifier: Channel] = [:]
    private var rng = SystemRandomNumberGenerator()
    private var serverChannel: Channel?

    public init(roomTTL: Double = RelayLimits.defaultRoomTTL) {
        self.roomTTL = roomTTL
    }

    /// Starts listening; returns the bound port (handy with port 0 in tests).
    public func start(host: String, port: Int) throws -> Int {
        let upgrader = NIOWebSocketServerUpgrader(
            maxFrameSize: RelayLimits.maxFrameBytes,
            shouldUpgrade: { channel, head in
                channel.eventLoop.makeSucceededFuture(head.uri == "/ws" ? HTTPHeaders() : nil)
            },
            upgradePipelineHandler: { channel, _ in
                channel.pipeline.addHandler(RelayFrameHandler(server: self))
            })
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(
                    withServerUpgrade: (upgraders: [upgrader], completionHandler: { _ in }))
            }
            .childChannelOption(ChannelOptions.socketOption(.tcp_nodelay), value: 1)
        let channel = try bootstrap.bind(host: host, port: port).wait()
        serverChannel = channel
        channel.eventLoop.scheduleRepeatedTask(initialDelay: .seconds(30), delay: .seconds(30)) { [weak self] _ in
            self?.expireRooms()
        }
        return channel.localAddress?.port ?? port
    }

    /// Blocks until the server stops (used by the executable).
    public func waitUntilClosed() throws {
        try serverChannel?.closeFuture.wait()
    }

    public func shutdown() async throws {
        try await serverChannel?.close()
        try await group.shutdownGracefully()
    }

    // MARK: Called on the event loop by RelayFrameHandler

    func connected(_ channel: Channel) {
        channels[ObjectIdentifier(channel)] = channel
    }

    func received(_ bytes: [UInt8], from channel: Channel) {
        perform(core.received(bytes, from: ObjectIdentifier(channel), now: Self.now(), using: &rng))
    }

    func disconnected(_ channel: Channel) {
        let id = ObjectIdentifier(channel)
        guard channels.removeValue(forKey: id) != nil else { return }
        perform(core.disconnected(id))
    }

    private func expireRooms() {
        perform(core.expire(now: Self.now(), ttl: roomTTL))
    }

    private func perform(_ actions: [RelayAction<ObjectIdentifier>]) {
        for action in actions {
            switch action {
            case .send(let bytes, let id):
                guard let channel = channels[id] else { continue }
                let frame = WebSocketFrame(fin: true, opcode: .binary, data: channel.allocator.buffer(bytes: bytes))
                channel.writeAndFlush(frame, promise: nil)
            case .close(let id):
                guard let channel = channels[id] else { continue }
                let frame = WebSocketFrame(fin: true, opcode: .connectionClose, data: channel.allocator.buffer(capacity: 0))
                channel.writeAndFlush(frame).whenComplete { _ in channel.close(promise: nil) }
            }
        }
    }

    private static func now() -> Double {
        Double(NIODeadline.now().uptimeNanoseconds) / 1e9
    }
}

/// Unwraps WebSocket frames for the server. The protocol uses only whole binary frames.
final class RelayFrameHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame

    private let server: RelayServer

    init(server: RelayServer) {
        self.server = server
    }

    func handlerAdded(context: ChannelHandlerContext) {
        server.connected(context.channel)
    }

    func channelInactive(context: ChannelHandlerContext) {
        server.disconnected(context.channel)
        context.fireChannelInactive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        switch frame.opcode {
        case .binary where frame.fin:
            server.received(Array(buffer: frame.unmaskedData), from: context.channel)
        case .ping:
            let pong = WebSocketFrame(fin: true, opcode: .pong, data: frame.unmaskedData)
            context.writeAndFlush(wrapOutboundOut(pong), promise: nil)
        case .pong:
            break
        default:   // close, text or fragmented frames: none are part of this protocol
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }
}
