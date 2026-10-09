import Testing
import TanksCore
@testable import TanksNet

@Test func integersAreLittleEndian() {
    var w = ByteWriter()
    w.u16(0x1234)
    w.u32(0xA1B2_C3D4)
    #expect(w.bytes == [0x34, 0x12, 0xD4, 0xC3, 0xB2, 0xA1])
}

@Test func primitivesRoundTrip() throws {
    var w = ByteWriter()
    w.u8(7)
    w.bool(true)
    w.u16(65535)
    w.u32(.max)
    w.u64(0x0102_0304_0506_0708)
    w.i16(-12345)
    w.f32(-1.5)
    w.f64(.pi)
    w.string("Grimsborough ✓")
    w.vec(Vec2(3, -4))
    var r = ByteReader(w.bytes)
    #expect(try r.u8() == 7)
    #expect(try r.bool() == true)
    #expect(try r.u16() == 65535)
    #expect(try r.u32() == .max)
    #expect(try r.u64() == 0x0102_0304_0506_0708)
    #expect(try r.i16() == -12345)
    #expect(try r.f32() == -1.5)
    #expect(try r.f64() == .pi)
    #expect(try r.string() == "Grimsborough ✓")
    #expect(try r.vec() == Vec2(3, -4))
    #expect(r.isAtEnd)
    try r.finish()
}

@Test func readingPastTheEndThrows() {
    var r = ByteReader([1])
    #expect(throws: WireError.truncated) { try r.u16() }
}

@Test func onlyZeroAndOneAreBools() {
    var r = ByteReader([2])
    #expect(throws: WireError.badValue("bool")) { try r.bool() }
}

@Test func nonFiniteFloatsAreRejected() {
    var w = ByteWriter()
    w.f32(.nan)
    w.f64(.infinity)
    var r = ByteReader(w.bytes)
    #expect(throws: WireError.badValue("float")) { try r.f32() }
    var r2 = ByteReader(Array(w.bytes.dropFirst(4)))
    #expect(throws: WireError.badValue("float")) { try r2.f64() }
}

@Test func longStringsAreCappedWhenWrittenAndRejectedWhenRead() throws {
    var w = ByteWriter()
    w.string(String(repeating: "x", count: 1000))
    var r = ByteReader(w.bytes)
    #expect(try r.string().count == ByteReader.maxStringLength)
    var hostile = ByteReader([0x2C, 0x01] + Array(repeating: 0x41, count: 300))   // claims 300 bytes
    #expect(throws: WireError.badValue("string length")) { try hostile.string() }
}

@Test func countsAboveTheCapAreRejected() {
    var r = ByteReader([10, 0])
    #expect(throws: WireError.badValue("count")) { try r.count(max: 9) }
}

@Test func leftoverBytesAreAnError() {
    let r = ByteReader([1])
    #expect(throws: WireError.trailingBytes) { try r.finish() }
}

@Test func randomRoomCodesAreWellFormed() {
    var rng = SeededRandom(seed: 1)
    for _ in 0..<200 {
        let code = TanksNet.randomRoomCode(using: &rng)
        #expect(code.count == 5)
        #expect(TanksNet.normalizeRoomCode(code) == code)
        #expect(!code.contains("I") && !code.contains("O"))
    }
}

@Test func roomCodesAreNormalizedFromWhatPeopleType() {
    #expect(TanksNet.normalizeRoomCode("kxwpq") == "KXWPQ")
    #expect(TanksNet.normalizeRoomCode(" kx-wp q ") == "KXWPQ")
    #expect(TanksNet.normalizeRoomCode("KXWP") == nil)        // too short
    #expect(TanksNet.normalizeRoomCode("KXWPQA") == nil)      // too long
    #expect(TanksNet.normalizeRoomCode("KXWPO") == nil)       // O is never used
    #expect(TanksNet.normalizeRoomCode("KX1PQ") == nil)       // digits are never used
}

@Test func relayMessagesRoundTrip() throws {
    let messages: [RelayMessage] = [
        .hello(version: TanksNet.protocolVersion), .createRoom, .roomCreated(code: "KXWPQ"), .joinRoom(code: "kxwpq"),
        .joined, .error(.roomFull), .error(.versionMismatch), .peerLeft,
    ]
    for message in messages {
        let bytes = message.encoded()
        #expect(RelayMessage.isControlFrame(bytes))
        #expect(try RelayMessage.decode(bytes) == message)
    }
}

@Test func relayDecodingRejectsUnknownTypesBadCodesAndLeftovers() {
    #expect(throws: (any Error).self) { try RelayMessage.decode([]) }
    #expect(throws: (any Error).self) { try RelayMessage.decode([9]) }
    #expect(throws: (any Error).self) { try RelayMessage.decode([6, 99]) }       // unknown error code
    #expect(throws: (any Error).self) { try RelayMessage.decode([2, 0]) }        // trailing byte
}

@Test func controlFramesAreThoseBelowTheFirstGameType() {
    #expect(RelayMessage.isControlFrame([5]))
    #expect(!RelayMessage.isControlFrame([RelayMessage.firstGameType]))
    #expect(!RelayMessage.isControlFrame([]))
}

@Test func errorCodesHaveMessagesForPlayers() {
    #expect(RelayErrorCode.roomNotFound.message == "Room not found")
    #expect(RelayErrorCode.versionMismatch.message == "Version mismatch — update the game")
}
