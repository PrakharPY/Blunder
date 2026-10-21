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

  factory MeshModel.fromData(
    Iterable<Vec3> positions,
    Iterable<MeshFace> meshFaces,
  ) =>
      MeshModel._(
        positions.map(MeshVertex.new).toList(),
        meshFaces.toList(),
      );

  factory MeshModel.starterPlane() {
    final mesh = MeshModel.empty();
    mesh.vertices.addAll([
      const MeshVertex(Vec3(-1, -1, 0)),
      const MeshVertex(Vec3(1, -1, 0)),
      const MeshVertex(Vec3(1, 1, 0)),
      const MeshVertex(Vec3(-1, 1, 0)),
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

  List<int> duplicateVertices(Iterable<int> selectedVertices) {
    final selection = selectedVertices.toSet().toList()..sort();
    if (selection.isEmpty ||
        selection.any((index) => index < 0 || index >= vertices.length)) {
      return [];
    }
    return selection
        .map((index) => addVertex(vertices[index].position))
        .toList();
  }

  int? duplicateFace(int faceIndex) {
    if (faceIndex < 0 || faceIndex >= faces.length) return null;
    final face = faces[faceIndex];
    final duplicatedVertices = duplicateVertices(face.vertices);
    final remapped = {
      for (var i = 0; i < face.vertices.length; i++)
        face.vertices[i]: duplicatedVertices[i],
    };
    faces.add(
      MeshFace(
        face.vertices.map((index) => remapped[index]!).toList(),
        face.uv,
      ),
    );
    return faces.length - 1;
  }

  bool moveVertices(Iterable<int> selectedVertices, Vec3 delta) {
    final selection = selectedVertices.toSet();
    if (selection.isEmpty ||
        selection.any((index) => index < 0 || index >= vertices.length)) {
      return false;
    }
    for (final index in selection) {
      final position = vertices[index].position;
      vertices[index] = MeshVertex(
        Vec3(
          position.x + delta.x,
          position.y + delta.y,
          position.z + delta.z,
        ),
      );
    }
    return true;
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
    final centerZ = selection
            .map((index) => vertices[index].position.z)
            .reduce((a, b) => a + b) /
        4;
    var normalX = 0.0;
    var normalY = 0.0;
    var normalZ = 0.0;
    var normalMagnitude = 0.0;
    for (var first = 0; first < selection.length; first++) {
      final origin = vertices[selection[first]].position;
      for (var second = first + 1; second < selection.length; second++) {
        final a = vertices[selection[second]].position;
        for (var third = second + 1; third < selection.length; third++) {
          final b = vertices[selection[third]].position;
          final candidateX = (a.y - origin.y) * (b.z - origin.z) -
              (a.z - origin.z) * (b.y - origin.y);
          final candidateY = (a.z - origin.z) * (b.x - origin.x) -
              (a.x - origin.x) * (b.z - origin.z);
          final candidateZ = (a.x - origin.x) * (b.y - origin.y) -
              (a.y - origin.y) * (b.x - origin.x);
          final magnitude = candidateX * candidateX +
              candidateY * candidateY +
              candidateZ * candidateZ;
          if (magnitude > normalMagnitude) {
            normalX = candidateX;
            normalY = candidateY;
            normalZ = candidateZ;
            normalMagnitude = magnitude;
          }
        }
      }
    }
    final normalComponents = [
      normalX.abs(),
      normalY.abs(),
      normalZ.abs(),
    ];
    var dominantAxis = 0;
    if (normalComponents[1] > normalComponents[dominantAxis]) {
      dominantAxis = 1;
    }
    if (normalComponents[2] > normalComponents[dominantAxis]) {
      dominantAxis = 2;
    }
    if ([normalX, normalY, normalZ][dominantAxis].abs() < 1e-8) return false;

    selection.sort((a, b) {
      final pointA = vertices[a].position;
      final pointB = vertices[b].position;
      final angleA = switch (dominantAxis) {
        0 => math.atan2(pointA.y - centerY, pointA.z - centerZ),
        1 => math.atan2(pointA.z - centerZ, pointA.x - centerX),
        _ => math.atan2(pointA.y - centerY, pointA.x - centerX),
      };
      final angleB = switch (dominantAxis) {
        0 => math.atan2(pointB.y - centerY, pointB.z - centerZ),
        1 => math.atan2(pointB.z - centerZ, pointB.x - centerX),
        _ => math.atan2(pointB.y - centerY, pointB.x - centerX),
      };
      return angleA.compareTo(angleB);
    });

    final area = _projectedSignedArea(selection, dominantAxis);
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

  double _projectedSignedArea(List<int> indices, int droppedAxis) {
    var area = 0.0;
    for (var i = 0; i < indices.length; i++) {
      final current = vertices[indices[i]].position;
      final next = vertices[indices[(i + 1) % indices.length]].position;
      final (currentX, currentY) = switch (droppedAxis) {
        0 => (current.y, current.z),
        1 => (current.z, current.x),
        _ => (current.x, current.y),
      };
      final (nextX, nextY) = switch (droppedAxis) {
        0 => (next.y, next.z),
        1 => (next.z, next.x),
        _ => (next.x, next.y),
      };
      area += currentX * nextY - nextX * currentY;
    }
    return area / 2;
  }

  bool _sameVertices(List<int> first, List<int> second) {
    return first.length == second.length && first.toSet().containsAll(second);
  }
}
