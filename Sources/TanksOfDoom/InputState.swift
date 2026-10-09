import TanksNet

struct InputState {
    var forward = false
    var backward = false
    var left = false
    var right = false
    var turretLeft = false
    var turretRight = false
    var space = false
    var fKey = false

    var firePrimary: Bool { space }
    var fireSecondary: Bool { fKey }
    var turretManualHeld: Bool { turretLeft || turretRight }
}

extension InputState {
    /// The keys as sent over the network (`InputFrame` held bits).
    init(bits: UInt8) {
        forward = bits & InputFrame.forward != 0
        backward = bits & InputFrame.backward != 0
        left = bits & InputFrame.left != 0
        right = bits & InputFrame.right != 0
        turretLeft = bits & InputFrame.turretLeft != 0
        turretRight = bits & InputFrame.turretRight != 0
        space = bits & InputFrame.fireMain != 0
        fKey = bits & InputFrame.fireMG != 0
    }

    var bits: UInt8 {
        var bits: UInt8 = 0
        if forward { bits |= InputFrame.forward }
        if backward { bits |= InputFrame.backward }
        if left { bits |= InputFrame.left }
        if right { bits |= InputFrame.right }
        if turretLeft { bits |= InputFrame.turretLeft }
        if turretRight { bits |= InputFrame.turretRight }
        if space { bits |= InputFrame.fireMain }
        if fKey { bits |= InputFrame.fireMG }
        return bits
    }
}
