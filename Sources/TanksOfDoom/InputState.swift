struct InputState {
    var forward = false
    var backward = false
    var left = false
    var right = false
    var turretLeft = false
    var turretRight = false
    var leftMouse = false
    var rightMouse = false
    var space = false
    var fKey = false

    var firePrimary: Bool { leftMouse || space }
    var fireSecondary: Bool { rightMouse || fKey }
    var turretManualHeld: Bool { turretLeft || turretRight }
}
