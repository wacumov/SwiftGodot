//
//  PlayerController.swift
//
//
//  Created by Marquis Kurt on 7/19/23.
//

import Foundation
import SwiftGodot

class PlayerController: CharacterBody2D {
    var acceleration: Float = 100
    var friction: Double = 100
    var speed: Double = 200

    var movementVector: Vector2 {
        var movement = Vector2.zero
        movement.x = Float(
            Input.shared.getActionStrength(action: "move_right") - Input.shared.getActionStrength(action: "move_left"))
        return movement.normalized()
    }

    required init() {
        super.init()
    }
    required init(nativeHandle: UnsafeRawPointer) {
        fatalError("init(nativeHandle:) not supported")
    }

    override func _physicsProcess(delta: Double) {
        if Engine.shared.isEditorHint() { return }
        if movementVector != .zero {
            let acceleratedVector = Vector2(x: acceleration, y: acceleration)
            let acceleratedMovement = movementVector * acceleratedVector
            self.velocity = acceleratedMovement.limitLength(length: speed)
        }
    }
}
