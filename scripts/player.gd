extends Node3D

@export var move_speed: float = 10.0
@export var mouse_sensitivity: float = 0.002

@onready var camera: Camera3D = $Camera3D

var yaw := 0.0
var pitch := 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
		rotation.y = yaw
		camera.rotation.x = pitch
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		dir -= transform.basis.z
	if Input.is_action_pressed("move_backward"):
		dir += transform.basis.z
	if Input.is_action_pressed("move_left"):
		dir -= transform.basis.x
	if Input.is_action_pressed("move_right"):
		dir += transform.basis.x
	if Input.is_action_pressed("move_up"):
		dir += transform.basis.y
	if Input.is_action_pressed("move_down"):
		dir -= transform.basis.y

	if dir != Vector3.ZERO:
		global_translate(dir.normalized() * move_speed * delta)
