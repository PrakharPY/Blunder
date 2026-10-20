import 'dart:math' as math;
import 'dart:ui' show Offset;

class Vec3 {
  const Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;
}

class MeshVertex {
  const MeshVertex(this.position);

  final Vec3 position;
}

class MeshFace {
  MeshFace(List<int> vertices, List<Offset> uv)
      : vertices = List.unmodifiable(vertices),
        uv = List.of(uv);

  final List<int> vertices;
  final List<Offset> uv;
}

class MeshModel {
  MeshModel._(this.vertices, this.faces);

  factory MeshModel.empty() => MeshModel._([], []);

  factory MeshModel.starterPlane() {
    final mesh = MeshModel.empty();
    mesh.vertices.addAll([
      MeshVertex(const Vec3(-1, -1, 0)),
      MeshVertex(const Vec3(1, -1, 0)),
      MeshVertex(const Vec3(1, 1, 0)),
      MeshVertex(const Vec3(-1, 1, 0)),
    ]);
    mesh.faces.add(
      MeshFace(
        const [0, 1, 2, 3],
        const [
          Offset(0.08, 0.08),
          Offset(0.92, 0.08),
          Offset(0.92, 0.92),
          Offset(0.08, 0.92),
        ],
      ),
    );
    return mesh;
  }

  final List<MeshVertex> vertices;
  final List<MeshFace> faces;

  int addVertex(Vec3 position) {
    vertices.add(MeshVertex(position));
    return vertices.length - 1;
  }

  bool addQuad(Iterable<int> selectedVertices) {
    final selection = selectedVertices.toSet().toList();
    if (selection.length != 4 ||
        selection.any((index) => index < 0 || index >= vertices.length)) {
      return false;
    }

    final centerX = selection
            .map((index) => vertices[index].position.x)
            .reduce((a, b) => a + b) /
        4;
    final centerY = selection
            .map((index) => vertices[index].position.y)
            .reduce((a, b) => a + b) /
        4;
    selection.sort((a, b) {
      final pointA = vertices[a].position;
      final pointB = vertices[b].position;
      return math.atan2(pointA.y - centerY, pointA.x - centerX)
          .compareTo(math.atan2(pointB.y - centerY, pointB.x - centerX));
    });

    final area = _signedArea(selection);
    if (area.abs() < 1e-8) return false;
    if (area < 0) selection.setAll(0, selection.reversed.toList());
    if (faces.any((face) => _sameVertices(face.vertices, selection))) {
      return false;
    }

    faces.add(
      MeshFace(
        selection,
        const [
          Offset(0.08, 0.08),
          Offset(0.92, 0.08),
          Offset(0.92, 0.92),
          Offset(0.08, 0.92),
        ],
      ),
    );
    return true;
  }

  bool removeFace(int faceIndex) {
    if (faceIndex < 0 || faceIndex >= faces.length) return false;
    faces.removeAt(faceIndex);
    return true;
  }

  bool updateUv(int faceIndex, int cornerIndex, Offset value) {
    if (faceIndex < 0 ||
        faceIndex >= faces.length ||
        cornerIndex < 0 ||
        cornerIndex >= 4) {
      return false;
    }
    faces[faceIndex].uv[cornerIndex] = Offset(
      value.dx.clamp(0.0, 1.0).toDouble(),
      value.dy.clamp(0.0, 1.0).toDouble(),
    );
    return true;
  }

  double _signedArea(List<int> indices) {
    var area = 0.0;
    for (var i = 0; i < indices.length; i++) {
      final current = vertices[indices[i]].position;
      final next = vertices[indices[(i + 1) % indices.length]].position;
      area += current.x * next.y - next.x * current.y;
    }
    return area / 2;
  }

  bool _sameVertices(List<int> first, List<int> second) {
    return first.length == second.length && first.toSet().containsAll(second);
  }
}
