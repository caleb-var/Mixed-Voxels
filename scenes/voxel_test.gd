extends Node3D

@export var player_path: NodePath
## Number of chunks to generate around the player for each LOD ring.
@export var chunk_radius: int = 2
## Total number of LOD levels. Add as many as desired.
@export var lod_count: int = 4
## Extra range before removing far chunks to reduce popping.
@export var hysteresis_margin: float = 0.2
## Chunk dimensions per LOD (in voxels).
@export var show_chunk_bounds: bool = false
@export var show_wireframe: bool = false
@onready var player: Node3D = get_node_or_null(player_path)

var mesher := BinaryGreedyMesher.new()
var noise := FastNoiseLite.new()

var _wire_shader := Shader.new()
var _voxel_wire_material := ShaderMaterial.new()
var _bounds_material := ShaderMaterial.new()

## Per‑LOD dictionaries of existing chunks.
var chunks: Array = []
## Last observed chunk-space centre for each LOD. Used to detect when
## to shift clipmap rings.
var last_centers: Array = []

## Holds voxel data and mesh instance for a single chunk.
class ChunkData:
	## Voxel materials stored as uint8 values (0 = empty, 1..255 = material id).
	var materials: PackedByteArray
	## Rendered mesh instance placed in the scene.
	var mesh: MeshInstance3D
	## Optional mesh outlining the chunk bounds.
	var bounds: MeshInstance3D

func _ready() -> void:
	_wire_shader.code = "shader_type spatial; render_mode unshaded, wireframe;"
	_voxel_wire_material.shader = _wire_shader
	_bounds_material.shader = _wire_shader
	_bounds_material.set_shader_parameter("albedo", Color.RED)

	noise.seed = randi()
	
	
