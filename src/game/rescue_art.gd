extends Node2D
const Painter = preload("res://src/game/renderer.gd")
var painter = Painter.new()
func _draw() -> void:
	painter.paint_ending(self)
