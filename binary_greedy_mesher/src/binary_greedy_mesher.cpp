#include "binary_greedy_mesher.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <vector>

using namespace godot;

static inline bool voxel_at(const uint8_t *data, int x, int y, int z, const Vector3i &size) {
    if (x < 0 || y < 0 || z < 0 || x >= size.x || y >= size.y || z >= size.z) {
        return false;
    }
    return data[x + size.x * (y + size.y * z)] != 0;
}

Ref<ArrayMesh> BinaryGreedyMesher::build_mesh(const PackedByteArray &voxels, const Vector3i &size, int lod) {
    Ref<ArrayMesh> mesh;
    mesh.instantiate();

    if (voxels.is_empty() || size.x <= 0 || size.y <= 0 || size.z <= 0) {
        return mesh;
    }

    const uint8_t *data = voxels.ptr();
    int dims[3] = {size.x, size.y, size.z};

    std::vector<Vector3> vertices;
    std::vector<Vector3> normals;
    std::vector<int> indices;

    int voxel_scale = 1 << lod;
    Vector3 scale((real_t)voxel_scale, (real_t)voxel_scale, (real_t)voxel_scale);

    for (int d = 0; d < 3; ++d) {
        int u = (d + 1) % 3;
        int v = (d + 2) % 3;

        std::vector<int> mask(dims[u] * dims[v]);
        int x[3] = {0, 0, 0};
        int q[3] = {0, 0, 0};
        q[d] = 1;

        for (x[d] = -1; x[d] < dims[d];) {
            // Build mask
            int n = 0;
            for (x[v] = 0; x[v] < dims[v]; ++x[v]) {
                for (x[u] = 0; x[u] < dims[u]; ++x[u]) {
                    bool a = (x[d] >= 0) ? voxel_at(data, x[0], x[1], x[2], size) : false;
                    bool b = (x[d] < dims[d] - 1) ? voxel_at(data, x[0] + q[0], x[1] + q[1], x[2] + q[2], size) : false;
                    mask[n++] = (a != b) ? (a ? 1 : -1) : 0;
                }
            }

            ++x[d];
            n = 0;

            for (int j = 0; j < dims[v]; ++j) {
                for (int i = 0; i < dims[u];) {
                    int c = mask[n];
                    if (c != 0) {
                        int w = 1;
                        while (i + w < dims[u] && mask[n + w] == c) {
                            ++w;
                        }
                        int h = 1;
                        bool done = false;
                        while (j + h < dims[v]) {
                            for (int k = 0; k < w; ++k) {
                                if (mask[n + k + h * dims[u]] != c) {
                                    done = true;
                                    break;
                                }
                            }
                            if (done) {
                                break;
                            }
                            ++h;
                        }

                        x[u] = i;
                        x[v] = j;

                        Vector3 du;
                        du[u] = w;
                        Vector3 dv;
                        dv[v] = h;
                        Vector3 pos((real_t)x[0], (real_t)x[1], (real_t)x[2]);
                        Vector3 normal;
                        normal[d] = c > 0 ? 1.0f : -1.0f;

                        int start = vertices.size();
                        if (c > 0) {
                            vertices.push_back((pos) * scale);
                            vertices.push_back((pos + du) * scale);
                            vertices.push_back((pos + dv) * scale);
                            vertices.push_back((pos + du + dv) * scale);

                            normals.insert(normals.end(), 4, normal);

                            indices.push_back(start + 0);
                            indices.push_back(start + 1);
                            indices.push_back(start + 2);
                            indices.push_back(start + 1);
                            indices.push_back(start + 3);
                            indices.push_back(start + 2);
                        } else {
                            Vector3 pos2 = pos + Vector3(q[0], q[1], q[2]);
                            vertices.push_back((pos2) * scale);
                            vertices.push_back((pos2 + dv) * scale);
                            vertices.push_back((pos2 + du) * scale);
                            vertices.push_back((pos2 + du + dv) * scale);

                            normals.insert(normals.end(), 4, normal);

                            indices.push_back(start + 0);
                            indices.push_back(start + 1);
                            indices.push_back(start + 2);
                            indices.push_back(start + 1);
                            indices.push_back(start + 3);
                            indices.push_back(start + 2);
                        }

                        for (int l = 0; l < h; ++l) {
                            for (int k = 0; k < w; ++k) {
                                mask[n + k + l * dims[u]] = 0;
                            }
                        }

                        i += w;
                        n += w;
                    } else {
                        ++i;
                        ++n;
                    }
                }
            }
        }
    }
    if (vertices.empty() || indices.empty()) {
        return mesh;
    }

    PackedVector3Array pvertices;
    pvertices.resize(vertices.size());
    for (int i = 0; i < vertices.size(); ++i) {
        pvertices[i] = vertices[i];
    }

    PackedVector3Array pnormals;
    pnormals.resize(normals.size());
    for (int i = 0; i < normals.size(); ++i) {
        pnormals[i] = normals[i];
    }

    PackedInt32Array pindices;
    pindices.resize(indices.size());
    for (int i = 0; i < indices.size(); ++i) {
        pindices[i] = indices[i];
    }

    Array arr;
    arr.resize(Mesh::ARRAY_MAX);
    arr[Mesh::ARRAY_VERTEX] = pvertices;
    arr[Mesh::ARRAY_NORMAL] = pnormals;
    arr[Mesh::ARRAY_INDEX] = pindices;

    mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arr);
    return mesh;
}

void BinaryGreedyMesher::_bind_methods() {
    ClassDB::bind_method(D_METHOD("build_mesh", "voxels", "size", "lod"), &BinaryGreedyMesher::build_mesh, DEFVAL(0));
}
