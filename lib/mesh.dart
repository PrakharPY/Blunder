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

  factory MeshModel.join(Iterable<MeshModel> meshes) {
    final joined = MeshModel.empty();
    for (final mesh in meshes) {
      final offset = joined.vertices.length;
      joined.vertices.addAll(mesh.vertices);
      joined.faces.addAll(
        mesh.faces.map(
          (face) => MeshFace(
            face.vertices.map((index) => index + offset).toList(),
            face.uv,
          ),
        ),
      );
    }
    return joined;
  }

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

  bool addGridSurface(
    List<Vec3> corners,
    int horizontalSteps,
    int verticalSteps,
  ) {
    if (corners.length != 4 ||
        horizontalSteps < 1 ||
        horizontalSteps > 64 ||
        verticalSteps < 1 ||
        verticalSteps > 64) {
      return false;
    }

    final firstVertex = vertices.length;
    final columns = horizontalSteps + 1;
    for (var row = 0; row <= verticalSteps; row++) {
      final vertical = row / verticalSteps;
      for (var column = 0; column <= horizontalSteps; column++) {
        final horizontal = column / horizontalSteps;
        final top = _interpolate(corners[0], corners[1], horizontal);
        final bottom = _interpolate(corners[3], corners[2], horizontal);
        vertices.add(
          MeshVertex(_interpolate(top, bottom, vertical)),
        );
      }
    }

    final uvByVertex = <int, Offset>{
      for (var row = 0; row <= verticalSteps; row++)
        for (var column = 0; column <= horizontalSteps; column++)
          firstVertex + row * columns + column: Offset(
            column / horizontalSteps,
            1 - row / verticalSteps,
          ),
    };
    final firstFace = faces.length;
    for (var row = 0; row < verticalSteps; row++) {
      for (var column = 0; column < horizontalSteps; column++) {
        final topLeft = firstVertex + row * columns + column;
        final topRight = topLeft + 1;
        final bottomLeft = topLeft + columns;
        final bottomRight = bottomLeft + 1;
        if (!addQuad([topLeft, topRight, bottomRight, bottomLeft])) {
          faces.removeRange(firstFace, faces.length);
          vertices.removeRange(firstVertex, vertices.length);
          return false;
        }
        final face = faces.last;
        face.uv.setAll(0, face.vertices.map((index) => uvByVertex[index]!));
      }
    }
    return true;
  }

  Vec3 _interpolate(Vec3 first, Vec3 second, double amount) => Vec3(
        first.x + (second.x - first.x) * amount,
        first.y + (second.y - first.y) * amount,
        first.z + (second.z - first.z) * amount,
      );

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

  bool addTriangle(Iterable<int> selectedVertices) {
    final selection = selectedVertices.toList();
    if (selection.length != 3 ||
        selection.toSet().length != 3 ||
        selection.any((index) => index < 0 || index >= vertices.length)) {
      return false;
    }
    MeshFace? previousFace;
    for (final face in faces.reversed) {
      if (face.vertices.length < 3) continue;
      var sharesEdge = false;
      for (var index = 0; index < face.vertices.length; index++) {
        final first = face.vertices[index];
        final second = face.vertices[(index + 1) % face.vertices.length];
        if ((first == selection[0] && second == selection[1]) ||
            (first == selection[1] && second == selection[0])) {
          sharesEdge = true;
          break;
        }
      }
      if (sharesEdge) {
        previousFace = face;
        break;
      }
    }
    if (previousFace != null) {
      Vec3 normal(List<int> faceVertices) {
        final a = vertices[faceVertices[0]].position;
        final b = vertices[faceVertices[1]].position;
        final c = vertices[faceVertices[2]].position;
        return Vec3(
          (b.y - a.y) * (c.z - a.z) - (b.z - a.z) * (c.y - a.y),
          (b.z - a.z) * (c.x - a.x) - (b.x - a.x) * (c.z - a.z),
          (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x),
        );
      }

      final previousNormal = normal(previousFace.vertices);
      final currentNormal = normal(selection);
      final alignment = previousNormal.x * currentNormal.x +
          previousNormal.y * currentNormal.y +
          previousNormal.z * currentNormal.z;
      if (alignment < 0) {
        final first = selection[0];
        selection[0] = selection[1];
        selection[1] = first;
      }
    }
    if (faces.any((face) => _sameVertices(face.vertices, selection))) {
      return false;
    }
    final a = vertices[selection[0]].position;
    final b = vertices[selection[1]].position;
    final c = vertices[selection[2]].position;
    final ab = Vec3(b.x - a.x, b.y - a.y, b.z - a.z);
    final ac = Vec3(c.x - a.x, c.y - a.y, c.z - a.z);
    final cross = Vec3(
      ab.y * ac.z - ab.z * ac.y,
      ab.z * ac.x - ab.x * ac.z,
      ab.x * ac.y - ab.y * ac.x,
    );
    if (cross.x * cross.x + cross.y * cross.y + cross.z * cross.z < 1e-12) {
      return false;
    }
    faces.add(
      MeshFace(
        selection,
        const [Offset(0.08, 0.08), Offset(0.92, 0.08), Offset(0.5, 0.92)],
      ),
    );
    return true;
  }

  bool joinVertices(Iterable<int> selectedVertices) {
    final selection = selectedVertices.toSet().toList()..sort();
    if (selection.length != 2 ||
        selection.any((index) => index < 0 || index >= vertices.length)) {
      return false;
    }

    final keep = selection.first;
    final remove = selection.last;
    final first = vertices[keep].position;
    final second = vertices[remove].position;
    vertices[keep] = MeshVertex(
      Vec3(
        (first.x + second.x) / 2,
        (first.y + second.y) / 2,
        (first.z + second.z) / 2,
      ),
    );

    final remainingFaces = <MeshFace>[];
    for (final face in faces) {
      final faceVertices = <int>[];
      final faceUvs = <Offset>[];
      for (var corner = 0; corner < face.vertices.length; corner++) {
        var index = face.vertices[corner];
        if (index == remove) {
          index = keep;
        } else if (index > remove) {
          index--;
        }
        if (faceVertices.isNotEmpty && faceVertices.last == index) continue;
        faceVertices.add(index);
        faceUvs.add(face.uv[corner]);
      }
      if (faceVertices.length > 1 && faceVertices.first == faceVertices.last) {
        faceVertices.removeLast();
        faceUvs.removeLast();
      }
      if (faceVertices.toSet().length >= 3) {
        remainingFaces.add(MeshFace(faceVertices, faceUvs));
      }
    }
    vertices.removeAt(remove);
    faces
      ..clear()
      ..addAll(remainingFaces);
    return true;
  }

  bool flipFaceNormals(Iterable<int> selectedFaces) {
    final selection = selectedFaces.toSet();
    if (selection.isEmpty ||
        selection.any((index) => index < 0 || index >= faces.length)) {
      return false;
    }
    for (final index in selection) {
      final face = faces[index];
      faces[index] = MeshFace(
        face.vertices.reversed.toList(),
        face.uv.reversed.toList(),
      );
    }
    return true;
  }

  int? mergeTriangles(Iterable<int> selectedFaces) {
    final indices = selectedFaces.toSet().toList()..sort();
    if (indices.length != 2 ||
        indices.any((index) => index < 0 || index >= faces.length)) {
      return null;
    }
    final first = faces[indices[0]];
    final second = faces[indices[1]];
    if (first.vertices.length != 3 || second.vertices.length != 3) return null;
    final allVertices = {...first.vertices, ...second.vertices};
    if (allVertices.length != 4) return null;

    final edges = <(int, int)>[];
    for (final face in [first, second]) {
      for (var corner = 0; corner < face.vertices.length; corner++) {
        final edge = (
          face.vertices[corner],
          face.vertices[(corner + 1) % face.vertices.length],
        );
        final sharedIndex = edges.indexWhere(
          (candidate) =>
              (candidate.$1 == edge.$1 && candidate.$2 == edge.$2) ||
              (candidate.$1 == edge.$2 && candidate.$2 == edge.$1),
        );
        if (sharedIndex >= 0) {
          edges.removeAt(sharedIndex);
        } else {
          edges.add(edge);
        }
      }
    }
    if (edges.length != 4) return null;

    final neighbors = <int, Set<int>>{};
    for (final edge in edges) {
      neighbors.putIfAbsent(edge.$1, () => {}).add(edge.$2);
      neighbors.putIfAbsent(edge.$2, () => {}).add(edge.$1);
    }
    if (neighbors.length != 4 ||
        neighbors.values.any((set) => set.length != 2)) {
      return null;
    }
    final orderedVertices = <int>[edges.first.$1];
    var previous = -1;
    var current = edges.first.$1;
    while (orderedVertices.length < 4) {
      final next =
          neighbors[current]!.firstWhere((vertex) => vertex != previous);
      if (orderedVertices.contains(next)) return null;
      orderedVertices.add(next);
      previous = current;
      current = next;
    }
    if (!neighbors[current]!.contains(orderedVertices.first)) return null;

    final uvByVertex = <int, List<Offset>>{};
    for (final face in [first, second]) {
      for (var corner = 0; corner < face.vertices.length; corner++) {
        uvByVertex
            .putIfAbsent(face.vertices[corner], () => [])
            .add(face.uv[corner]);
      }
    }
    final mergedUv = orderedVertices.map((vertex) {
      final values = uvByVertex[vertex]!;
      return Offset(
        values.map((value) => value.dx).reduce((a, b) => a + b) / values.length,
        values.map((value) => value.dy).reduce((a, b) => a + b) / values.length,
      );
    }).toList();

    for (final index in indices.reversed) {
      faces.removeAt(index);
    }
    faces.add(MeshFace(orderedVertices, mergedUv));
    return faces.length - 1;
  }

  bool rotateVertices(
    Iterable<int> selectedVertices,
    int axis,
    double degrees,
  ) {
    final selection = selectedVertices.toSet().toList();
    if (selection.isEmpty ||
        selection.any((index) => index < 0 || index >= vertices.length) ||
        axis < 0 ||
        axis > 2) {
      return false;
    }
    final center = Vec3(
      selection
              .map((index) => vertices[index].position.x)
              .reduce((a, b) => a + b) /
          selection.length,
      selection
              .map((index) => vertices[index].position.y)
              .reduce((a, b) => a + b) /
          selection.length,
      selection
              .map((index) => vertices[index].position.z)
              .reduce((a, b) => a + b) /
          selection.length,
    );
    final radians = degrees * math.pi / 180;
    final cosine = math.cos(radians);
    final sine = math.sin(radians);
    for (final index in selection) {
      final point = vertices[index].position;
      final x = point.x - center.x;
      final y = point.y - center.y;
      final z = point.z - center.z;
      final rotated = switch (axis) {
        0 => Vec3(x, y * cosine - z * sine, y * sine + z * cosine),
        1 => Vec3(x * cosine + z * sine, y, -x * sine + z * cosine),
        _ => Vec3(x * cosine - y * sine, x * sine + y * cosine, z),
      };
      vertices[index] = MeshVertex(
        Vec3(
          rotated.x + center.x,
          rotated.y + center.y,
          rotated.z + center.z,
        ),
      );
    }
    return true;
  }

  bool mirror(int axis) {
    if (axis < 0 || axis > 2 || vertices.isEmpty) return false;
    for (var index = 0; index < vertices.length; index++) {
      final point = vertices[index].position;
      vertices[index] = MeshVertex(
        switch (axis) {
          0 => Vec3(-point.x, point.y, point.z),
          1 => Vec3(point.x, -point.y, point.z),
          _ => Vec3(point.x, point.y, -point.z),
        },
      );
    }
    for (var index = 0; index < faces.length; index++) {
      final face = faces[index];
      faces[index] = MeshFace(
        face.vertices.reversed.toList(),
        face.uv.reversed.toList(),
      );
    }
    return true;
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

  bool scaleUniform(double factor) {
    if (vertices.isEmpty || !factor.isFinite || factor <= 0) return false;
    final center = Vec3(
      vertices.map((vertex) => vertex.position.x).reduce((a, b) => a + b) /
          vertices.length,
      vertices.map((vertex) => vertex.position.y).reduce((a, b) => a + b) /
          vertices.length,
      vertices.map((vertex) => vertex.position.z).reduce((a, b) => a + b) /
          vertices.length,
    );
    for (var index = 0; index < vertices.length; index++) {
      final point = vertices[index].position;
      vertices[index] = MeshVertex(
        Vec3(
          center.x + (point.x - center.x) * factor,
          center.y + (point.y - center.y) * factor,
          center.z + (point.z - center.z) * factor,
        ),
      );
    }
    return true;
  }

  bool deleteVertices(Iterable<int> selectedVertices) {
    final selection = selectedVertices.toSet();
    if (selection.isEmpty ||
        selection.any((index) => index < 0 || index >= vertices.length)) {
      return false;
    }
    faces.removeWhere((face) => face.vertices.any(selection.contains));
    final remap = <int, int>{};
    final remaining = <MeshVertex>[];
    for (var index = 0; index < vertices.length; index++) {
      if (selection.contains(index)) continue;
      remap[index] = remaining.length;
      remaining.add(vertices[index]);
    }
    for (var index = 0; index < faces.length; index++) {
      final face = faces[index];
      faces[index] = MeshFace(
        face.vertices.map((vertex) => remap[vertex]!).toList(),
        face.uv,
      );
    }
    vertices
      ..clear()
      ..addAll(remaining);
    return true;
  }

  bool deleteFaces(Iterable<int> selectedFaces) {
    final selection = selectedFaces.toSet();
    if (selection.isEmpty ||
        selection.any((index) => index < 0 || index >= faces.length)) {
      return false;
    }
    final remainingFaces = <MeshFace>[
      for (var index = 0; index < faces.length; index++)
        if (!selection.contains(index)) faces[index],
    ];
    faces
      ..clear()
      ..addAll(remainingFaces);
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
        cornerIndex >= faces[faceIndex].uv.length) {
      return false;
    }
    faces[faceIndex].uv[cornerIndex] = Offset(
      value.dx.clamp(0.0, 1.0).toDouble(),
      value.dy.clamp(0.0, 1.0).toDouble(),
    );
    return true;
  }

  bool smartUvRemap() {
    if (faces.isEmpty) return false;

    final columns = math.sqrt(faces.length).ceil();
    final rows = (faces.length / columns).ceil();
    final cellWidth = 1 / columns;
    final cellHeight = 1 / rows;
    final margin = math.min(cellWidth, cellHeight) * 0.08;

    for (var faceIndex = 0; faceIndex < faces.length; faceIndex++) {
      final face = faces[faceIndex];
      final positions =
          face.vertices.map((index) => vertices[index].position).toList();
      var normalX = 0.0;
      var normalY = 0.0;
      var normalZ = 0.0;
      for (var index = 0; index < positions.length; index++) {
        final current = positions[index];
        final next = positions[(index + 1) % positions.length];
        normalX += (current.y - next.y) * (current.z + next.z);
        normalY += (current.z - next.z) * (current.x + next.x);
        normalZ += (current.x - next.x) * (current.y + next.y);
      }
      final components = [normalX.abs(), normalY.abs(), normalZ.abs()];
      var droppedAxis = 0;
      if (components[1] > components[droppedAxis]) droppedAxis = 1;
      if (components[2] > components[droppedAxis]) droppedAxis = 2;
      final projected = positions.map((point) {
        return switch (droppedAxis) {
          0 => Offset(point.y, point.z),
          1 => Offset(point.z, point.x),
          _ => Offset(point.x, point.y),
        };
      }).toList();
      final minX = projected.map((point) => point.dx).reduce(math.min);
      final maxX = projected.map((point) => point.dx).reduce(math.max);
      final minY = projected.map((point) => point.dy).reduce(math.min);
      final maxY = projected.map((point) => point.dy).reduce(math.max);
      final spanX = maxX - minX;
      final spanY = maxY - minY;
      final availableWidth = cellWidth - margin * 2;
      final availableHeight = cellHeight - margin * 2;
      final scale = math.min(
        availableWidth / math.max(spanX, 1e-8),
        availableHeight / math.max(spanY, 1e-8),
      );
      final offsetX = (faceIndex % columns) * cellWidth;
      final offsetY = 1 - ((faceIndex ~/ columns) + 1) * cellHeight;
      final usedWidth = spanX * scale;
      final usedHeight = spanY * scale;
      final centeredX = offsetX + (cellWidth - usedWidth) / 2;
      final centeredY = offsetY + (cellHeight - usedHeight) / 2;
      face.uv
        ..clear()
        ..addAll(
          projected.map(
            (point) => Offset(
              centeredX + (point.dx - minX) * scale,
              centeredY + (point.dy - minY) * scale,
            ),
          ),
        );
    }
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
