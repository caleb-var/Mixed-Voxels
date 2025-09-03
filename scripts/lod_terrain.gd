extends Node3D

@export var player_path: NodePath
## Number of chunks to generate around the player for each LOD ring.
@export var chunk_radius: int = 2
## Total number of LOD levels. Add as many as desired.
@export var lod_count: int = 4
## Extra range before removing far chunks to reduce popping.
@export var hysteresis_margin: float = 0.2
## Number of voxels per side for all chunks.
@export var chunk_dim: int = 16

@onready var player: Node3D = get_node_or_null(player_path)

var _wire_shader := Shader.new()
var _lod_materials: Array = []
var lod_colors := [
        Color.RED,
        Color.GREEN,
        Color.BLUE,
        Color.YELLOW,
        Color.PURPLE,
        Color.CYAN
]

## Per‑LOD dictionaries of existing chunks.
var chunks: Array = []
## Last observed chunk-space centre for each LOD. Used to detect when
## to shift clipmap rings.
var last_centers: Array = []

## Holds mesh instance for a single chunk.
class ChunkData:
        var mesh: MeshInstance3D

func _ready() -> void:
        _wire_shader.code = "shader_type spatial; render_mode unshaded, wireframe;"
        for i in range(lod_count):
                var mat := ShaderMaterial.new()
                mat.shader = _wire_shader
                mat.set_shader_parameter("albedo", lod_colors[i % lod_colors.size()])
                _lod_materials.append(mat)
                chunks.append({})
                last_centers.append(Vector3i(1_000_000, 1_000_000, 1_000_000))
        _update_chunks(true)

func _process(_delta: float) -> void:
        _update_chunks()

func _update_chunks(force: bool = false) -> void:
        if player == null:
                return

        var player_pos: Vector3 = player.global_transform.origin

        for lod in range(lod_count):
                var voxel_scale := 1 << lod               # 1×, 2×, 4×, 8× ...
                var world_size := chunk_dim * voxel_scale  # Chunk size in world units

                var center := Vector3i(
                        int(floor(player_pos.x / world_size)),
                        0,
                        int(floor(player_pos.z / world_size))
                )

                var lod_chunks: Dictionary = chunks[lod]

                if force or center != last_centers[lod]:
                        var wanted := {}

                        # Ensure all chunks in the visible plane exist.
                        for x in range(center.x - chunk_radius, center.x + chunk_radius + 1):
                                for z in range(center.z - chunk_radius, center.z + chunk_radius + 1):
                                        var key := Vector3i(x, 0, z)
                                        wanted[key] = true
                                        if not lod_chunks.has(key):
                                                lod_chunks[key] = _create_chunk(key, voxel_scale, lod)

                        # Remove chunks that moved outside the square with hysteresis margin.
                        var remove_radius := int(ceil(chunk_radius * (1.0 + hysteresis_margin)))
                        for k in lod_chunks.keys():
                                var dx = abs(k.x - center.x)
                                var dz = abs(k.z - center.z)
                                if dx > remove_radius or dz > remove_radius:
                                        lod_chunks[k].mesh.queue_free()
                                        lod_chunks.erase(k)

                        chunks[lod] = lod_chunks
                        last_centers[lod] = center

func _make_bounds_mesh(size: Vector3) -> Mesh:
        var m := ImmediateMesh.new()
        m.surface_begin(Mesh.PRIMITIVE_LINES)
        var x := size.x
        var y := size.y
        var z := size.z
        var pts := [
                Vector3(0, 0, 0), Vector3(x, 0, 0),
                Vector3(x, 0, 0), Vector3(x, y, 0),
                Vector3(x, y, 0), Vector3(0, y, 0),
                Vector3(0, y, 0), Vector3(0, 0, 0),
                Vector3(0, 0, z), Vector3(x, 0, z),
                Vector3(x, 0, z), Vector3(x, y, z),
                Vector3(x, y, z), Vector3(0, y, z),
                Vector3(0, y, z), Vector3(0, 0, z),
                Vector3(0, 0, 0), Vector3(0, 0, z),
                Vector3(x, 0, 0), Vector3(x, 0, z),
                Vector3(x, y, 0), Vector3(x, y, z),
                Vector3(0, y, 0), Vector3(0, y, z)
        ]
        for p in pts:
                m.surface_add_vertex(p)
        m.surface_end()
        return m

func _create_chunk(coord: Vector3i, voxel_scale: int, lod: int) -> ChunkData:
        var world_size := chunk_dim * voxel_scale
        var inst := MeshInstance3D.new()
        inst.mesh = _make_bounds_mesh(Vector3(world_size, world_size, world_size))
        inst.position = Vector3(
                coord.x * world_size,
                0,
                coord.z * world_size
        )
        inst.material_override = _lod_materials[lod]
        add_child(inst)

        var data := ChunkData.new()
        data.mesh = inst
        return data

