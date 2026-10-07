struct InputState {
    var forward = false
    var backward = false
    var left = false
    var right = false
    var leftMouse = false
    var rightMouse = false
    var space = false

    var firePrimary: Bool { leftMouse }
    var fireSecondary: Bool { rightMouse || space }
}
