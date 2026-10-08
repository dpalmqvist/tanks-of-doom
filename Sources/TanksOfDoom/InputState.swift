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
