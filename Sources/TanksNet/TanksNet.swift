import Foundation

public enum TanksNet {
    /// Bump on any change to the bytes on the wire; the relay turns away games that disagree.
    public static let protocolVersion: UInt16 = 1
    public static let roomCodeLength = 5
    /// No I or O, so a code read aloud can't be mistaken for 1 or 0.
    public static let roomCodeAlphabet: [Character] = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")

    public static func randomRoomCode(using rng: inout some RandomNumberGenerator) -> String {
        String((0..<roomCodeLength).map { _ in roomCodeAlphabet.randomElement(using: &rng)! })
    }

    /// Upper-cases and drops spaces and dashes; nil unless what's left is a well-formed code.
    public static func normalizeRoomCode(_ input: String) -> String? {
        let code = input.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard code.count == roomCodeLength, code.allSatisfy(roomCodeAlphabet.contains) else { return nil }
        return code
    }
}
