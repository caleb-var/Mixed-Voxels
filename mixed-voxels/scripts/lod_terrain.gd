extends Node3D

## Basic clipmap-based LOD terrain generator.
##
## Chunks are generated in concentric rings around a player position.
## Each subsequent ring doubles the voxel size (`1, 2, 4, 8, ...`),
## allowing an arbitrary number of LOD tiers. Rings only shift when the
## player crosses a chunk boundary. Border voxels are duplicated to
## create skirts that hide cracks between neighbouring LOD meshes.

@export var player_path: NodePath
## Number of chunks to generate around the player for each LOD ring.
@export var chunk_radius: int = 2
## Total number of LOD levels. Add as many as desired.
@export var lod_count: int = 4
## Extra range before removing far chunks to reduce popping.
@export var hysteresis_margin: float = 0.2
## Chunk dimensions per LOD (in voxels).
## Supply one size per LOD; the last value is reused if more levels are requested.
@export var lod_chunk_dims: PackedInt32Array = [32, 64, 64, 64]

@onready var player: Node3D = get_node_or_null(player_path)

var mesher := BinaryGreedyMesher.new()
var noise := FastNoiseLite.new()

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

func _ready() -> void:
    noise.seed = randi()
    # Prepare per‑LOD dictionaries and sentinel centres.
    for i in range(lod_count):
        chunks.append({})
        last_centers.append(Vector3i(1_000_000, 1_000_000, 1_000_000))
    # Initial generation around the player.
    _update_chunks(true)

func _process(_delta: float) -> void:
    _update_chunks()

func _update_chunks(force: bool = false) -> void:
    if player == null:
        return

    var player_pos: Vector3 = player.global_transform.origin

    for lod in range(lod_count):
        var voxel_scale := 1 << lod               # 1×, 2×, 4×, 8× ...
        var dim := lod_chunk_dims[min(lod, lod_chunk_dims.size() - 1)]
        var world_size := dim * voxel_scale       # Chunk size in world units

        var center := Vector3i(
            int(floor(player_pos.x / world_size)),
            int(floor(player_pos.y / world_size)),
            int(floor(player_pos.z / world_size))
        )

        var lod_chunks: Dictionary = chunks[lod]

        if force or center != last_centers[lod]:
            var wanted := {}

            # Ensure all chunks in the visible cube exist.
            for x in range(center.x - chunk_radius, center.x + chunk_radius + 1):
                for y in range(center.y - chunk_radius, center.y + chunk_radius + 1):
                    for z in range(center.z - chunk_radius, center.z + chunk_radius + 1):
                        var key := Vector3i(x, y, z)
                        wanted[key] = true
                        if not lod_chunks.has(key):
                            lod_chunks[key] = _create_chunk(key, dim, voxel_scale, lod)

            # Remove chunks that moved outside the cube with hysteresis margin.
            var remove_radius := int(ceil(chunk_radius * (1.0 + hysteresis_margin)))
            for k in lod_chunks.keys():
                var dx := abs(k.x - center.x)
                var dy := abs(k.y - center.y)
                var dz := abs(k.z - center.z)
                if dx > remove_radius or dy > remove_radius or dz > remove_radius:
                    lod_chunks[k].mesh.queue_free()
                    lod_chunks.erase(k)

            chunks[lod] = lod_chunks
            last_centers[lod] = center

func _create_chunk(coord: Vector3i, dim: int, voxel_scale: int, lod: int) -> ChunkData:
    # Duplicate border voxels to create skirts that hide seams.
    var side := dim + 1
    var vox := PackedByteArray()
    vox.resize(side * side * side)

    # Fill voxel buffer with basic heightmap data.
    for z in range(side):
        for y in range(side):
            for x in range(side):
                var gx := coord.x * dim + x
                var gy := coord.y * dim + y
                var gz := coord.z * dim + z
                var world_x := gx * voxel_scale
                var world_y := gy * voxel_scale
                var world_z := gz * voxel_scale
                var height := noise.get_noise_2d(world_x, world_z) * 8.0 + 16.0
                var idx := x + side * (y + side * z)
                vox[idx] = world_y < height ? 1 : 0

    var mesh := mesher.build_mesh(vox, Vector3i(side, side, side), voxel_scale)
    var inst := MeshInstance3D.new()
    inst.mesh = mesh
    inst.position = Vector3(
        coord.x * dim * voxel_scale,
        coord.y * dim * voxel_scale,
        coord.z * dim * voxel_scale
    )
    add_child(inst)

    var data := ChunkData.new()
    data.materials = vox
    data.mesh = inst
    return data

