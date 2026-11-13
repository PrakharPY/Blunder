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
  MeshFace(
    List<int> vertices,
    List<Offset> uv, {
    this.rvType = 0,
    this.rvTextureIndex = 0,
    List<int>? rvColors,
    this.rvExtraColor,
    this.rvExtraUv,
    this.rvEnvironmentColor,
  })  : vertices = List.unmodifiable(vertices),
        uv = List.of(uv),
        rvColors = List.of(rvColors ?? const <int>[]);

  final List<int> vertices;
  final List<Offset> uv;
  final int rvType;
  final int rvTextureIndex;
  final List<int> rvColors;
  final int? rvExtraColor;
  final Offset? rvExtraUv;
  int? rvEnvironmentColor;

  static MeshFace copyOf(
    MeshFace face, {
    List<int>? vertices,
    List<Offset>? uv,
    int? rvType,
    int? rvTextureIndex,
    List<int>? rvColors,
    int? rvExtraColor,
    Offset? rvExtraUv,
    int? rvEnvironmentColor,
  }) =>
      MeshFace(
        vertices ?? face.vertices,
        uv ?? face.uv,
        rvType: rvType ?? face.rvType,
        rvTextureIndex: rvTextureIndex ?? face.rvTextureIndex,
        rvColors: rvColors ?? face.rvColors,
        rvExtraColor: rvExtraColor ?? face.rvExtraColor,
        rvExtraUv: rvExtraUv ?? face.rvExtraUv,
        rvEnvironmentColor: rvEnvironmentColor ?? face.rvEnvironmentColor,
      );
}

class _UvChart {
  const _UvChart(this.faceUvs, this.minX, this.minY, this.maxX, this.maxY);

  final Map<int, List<Offset>> faceUvs;
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;

  double get width => maxX - minX;
  double get height => maxY - minY;
}

class _UvChartPlacement {
  const _UvChartPlacement(this.chart, this.x, this.y, this.scale);

  final _UvChart chart;
  final double x;
  final double y;
  final double scale;
}

class MeshModel {
  static const int maxFaceCount = 100000;
  static const double _uvChartNormalDot = 0.5;

  MeshModel._(this.vertices, this.faces, {this.smoothShading = false});

  factory MeshModel.empty() => MeshModel._([], []);

  factory MeshModel.fromData(
    Iterable<Vec3> positions,
    Iterable<MeshFace> meshFaces, {
    bool smoothShading = false,
  }) =>
      MeshModel._(
        positions.map(MeshVertex.new).toList(),
        meshFaces.toList(),
        smoothShading: smoothShading,
      );

  factory MeshModel.join(Iterable<MeshModel> meshes) {
    final meshList = meshes.toList();
    final joined = MeshModel.empty();
    joined.smoothShading =
        meshList.isNotEmpty && meshList.every((mesh) => mesh.smoothShading);
    for (final mesh in meshList) {
      final offset = joined.vertices.length;
      joined.vertices.addAll(mesh.vertices);
      joined.faces.addAll(
        mesh.faces.map(
          (face) => MeshFace.copyOf(
            face,
            vertices: face.vertices.map((index) => index + offset).toList(),
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
  bool smoothShading;

  static MeshModel rectangle() => MeshModel.starterPlane();

  static MeshModel circle({int segments = 32}) {
    final count = segments.clamp(8, 128).toInt();
    final vertices = [
      for (var index = 0; index < count; index++)
        Vec3(
          math.cos(index * math.pi * 2 / count),
          math.sin(index * math.pi * 2 / count),
          0,
        ),
    ];
    final mesh = MeshModel.fromData(vertices, [
      MeshFace(
        List.generate(count, (index) => index),
        [
          for (final vertex in vertices)
            Offset((vertex.x + 1) / 2, (vertex.y + 1) / 2),
        ],
      ),
    ]);
    return mesh;
  }

  static MeshModel cube() {
    const positions = [
      Vec3(-1, -1, -1),
      Vec3(1, -1, -1),
      Vec3(1, 1, -1),
      Vec3(-1, 1, -1),
      Vec3(-1, -1, 1),
      Vec3(1, -1, 1),
      Vec3(1, 1, 1),
      Vec3(-1, 1, 1),
    ];
    const faceVertices = [
      [0, 3, 2, 1],
      [4, 5, 6, 7],
      [0, 1, 5, 4],
      [3, 7, 6, 2],
      [0, 4, 7, 3],
      [1, 2, 6, 5],
    ];
    const faceUvs = [
      Offset(0, 0),
      Offset(1, 0),
      Offset(1, 1),
      Offset(0, 1),
    ];
    return MeshModel.fromData(
      positions,
      faceVertices.map((face) => MeshFace(face, faceUvs)),
    );
  }

  static MeshModel cylinder({int segments = 24}) {
    final count = segments.clamp(8, 128).toInt();
    final positions = <Vec3>[
      for (var level = 0; level < 2; level++)
        for (var index = 0; index < count; index++)
          Vec3(
            math.cos(index * math.pi * 2 / count),
            math.sin(index * math.pi * 2 / count),
            level == 0 ? -1 : 1,
          ),
    ];
    final faces = <MeshFace>[];
    for (var index = 0; index < count; index++) {
      final next = (index + 1) % count;
      faces.add(
        MeshFace(
          [index, next, count + next, count + index],
          [
            Offset(index / count, 0),
            Offset((index + 1) / count, 0),
            Offset((index + 1) / count, 1),
            Offset(index / count, 1),
          ],
        ),
      );
    }
    faces
      ..add(
        MeshFace(
          List.generate(count, (index) => count - index - 1),
          [
            for (var index = count - 1; index >= 0; index--)
              Offset(
                (positions[index].x + 1) / 2,
                (positions[index].y + 1) / 2,
              ),
          ],
        ),
      )
      ..add(
        MeshFace(
          List.generate(count, (index) => count + index),
          [
            for (var index = 0; index < count; index++)
              Offset(
                (positions[count + index].x + 1) / 2,
                (positions[count + index].y + 1) / 2,
              ),
          ],
        ),
      );
    return MeshModel.fromData(positions, faces);
  }

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
        faces.length + horizontalSteps * verticalSteps > maxFaceCount ||
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
        faces.length >= maxFaceCount ||
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
      final faceColors = <int>[];
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
        if (corner < face.rvColors.length) {
          faceColors.add(face.rvColors[corner]);
        }
      }
      if (faceVertices.length > 1 && faceVertices.first == faceVertices.last) {
        faceVertices.removeLast();
        faceUvs.removeLast();
        if (faceColors.isNotEmpty) faceColors.removeLast();
      }
      if (faceVertices.toSet().length >= 3) {
        remainingFaces.add(
          MeshFace.copyOf(
            face,
            vertices: faceVertices,
            uv: faceUvs,
            rvColors: faceColors,
          ),
        );
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
      faces[index] = MeshFace.copyOf(
        face,
        vertices: face.vertices.reversed.toList(),
        uv: face.uv.reversed.toList(),
        rvColors: face.rvColors.reversed.toList(),
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
    if (first.rvType != second.rvType ||
        first.rvTextureIndex != second.rvTextureIndex ||
        first.rvEnvironmentColor != second.rvEnvironmentColor) {
      return null;
    }
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
    final colorsByVertex = <int, List<int>>{};
    for (final face in [first, second]) {
      for (var corner = 0; corner < face.vertices.length; corner++) {
        colorsByVertex.putIfAbsent(face.vertices[corner], () => []).add(
            corner < face.rvColors.length ? face.rvColors[corner] : 0xffffffff);
      }
    }
    final mergedColors =
        orderedVertices.map((vertex) => colorsByVertex[vertex]!.first).toList();

    for (final index in indices.reversed) {
      faces.removeAt(index);
    }
    faces.add(
      MeshFace(
        orderedVertices,
        mergedUv,
        rvType: first.rvType,
        rvTextureIndex: first.rvTextureIndex,
        rvColors: mergedColors,
        rvEnvironmentColor: first.rvEnvironmentColor,
      ),
    );
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
      faces[index] = MeshFace.copyOf(
        face,
        vertices: face.vertices.reversed.toList(),
        uv: face.uv.reversed.toList(),
        rvColors: face.rvColors.reversed.toList(),
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
      MeshFace.copyOf(
        face,
        vertices: face.vertices.map((index) => remapped[index]!).toList(),
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
      faces[index] = MeshFace.copyOf(
        face,
        vertices: face.vertices.map((vertex) => remap[vertex]!).toList(),
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
        faces.length >= maxFaceCount ||
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

  bool smartUvRemap([Iterable<int>? selectedFaces]) {
    final selection = selectedFaces?.toSet().toList() ??
        List<int>.generate(faces.length, (index) => index);
    selection.sort();
    if (selection.isEmpty ||
        selection.any(
          (index) =>
              index < 0 ||
              index >= faces.length ||
              faces[index].vertices.any(
                    (vertex) => vertex < 0 || vertex >= vertices.length,
                  ),
        )) {
      return false;
    }

    final normals = <int, Vec3>{};
    final localCoordinates = <int, List<Offset>>{};
    final edgeFaces = <(int, int), List<int>>{};
    for (final faceIndex in selection) {
      final face = faces[faceIndex];
      normals[faceIndex] = _faceNormal(face);
      localCoordinates[faceIndex] = _faceLocalCoordinates(face);
      for (var corner = 0; corner < face.vertices.length; corner++) {
        final first = face.vertices[corner];
        final second = face.vertices[(corner + 1) % face.vertices.length];
        final edge = first < second ? (first, second) : (second, first);
        edgeFaces.putIfAbsent(edge, () => []).add(faceIndex);
      }
    }

    final adjacency = <int, List<(int, int, int)>>{
      for (final faceIndex in selection) faceIndex: [],
    };
    for (final entry in edgeFaces.entries) {
      final connectedFaces = entry.value;
      for (var first = 0; first < connectedFaces.length; first++) {
        for (var second = first + 1; second < connectedFaces.length; second++) {
          final firstFace = connectedFaces[first];
          final secondFace = connectedFaces[second];
          if (_dot(normals[firstFace]!, normals[secondFace]!) <
              _uvChartNormalDot) {
            continue;
          }
          adjacency[firstFace]!.add(
            (secondFace, entry.key.$1, entry.key.$2),
          );
          adjacency[secondFace]!.add(
            (firstFace, entry.key.$1, entry.key.$2),
          );
        }
      }
    }

    final visited = <int>{};
    final charts = <_UvChart>[];
    for (final seed in selection) {
      if (!visited.add(seed)) continue;
      final component = <int>[seed];
      final queue = <int>[seed];
      for (var cursor = 0; cursor < queue.length; cursor++) {
        for (final (neighbor, _, _) in adjacency[queue[cursor]]!) {
          if (_dot(normals[seed]!, normals[neighbor]!) < _uvChartNormalDot) {
            continue;
          }
          if (visited.add(neighbor)) {
            queue.add(neighbor);
            component.add(neighbor);
          }
        }
      }

      final componentSet = component.toSet();
      final chartUvs = <int, List<Offset>>{
        seed: List.of(localCoordinates[seed]!),
      };
      final unfolded = <int>{seed};
      final unfoldQueue = <int>[seed];
      for (var cursor = 0; cursor < unfoldQueue.length; cursor++) {
        final parent = unfoldQueue[cursor];
        for (final (child, edgeA, edgeB) in adjacency[parent]!) {
          if (!componentSet.contains(child) || !unfolded.add(child)) continue;
          final childUvs = _unfoldFaceAcrossEdge(
            parent,
            child,
            edgeA,
            edgeB,
            chartUvs[parent]!,
            localCoordinates[child]!,
          );
          if (childUvs == null) {
            unfolded.remove(child);
            continue;
          }
          chartUvs[child] = childUvs;
          unfoldQueue.add(child);
        }
      }
      if (chartUvs.length != component.length) {
        for (final faceIndex in component) {
          chartUvs.putIfAbsent(
            faceIndex,
            () => List.of(localCoordinates[faceIndex]!),
          );
        }
      }
      charts.add(_createUvChart(chartUvs));
    }

    final placements = _packUvCharts(charts);
    if (placements == null) return false;
    for (final placement in placements) {
      final chart = placement.chart;
      for (final entry in chart.faceUvs.entries) {
        faces[entry.key].uv
          ..clear()
          ..addAll(
            entry.value.map(
              (uv) => Offset(
                placement.x + (uv.dx - chart.minX) * placement.scale,
                placement.y + (uv.dy - chart.minY) * placement.scale,
              ),
            ),
          );
      }
    }
    return true;
  }

  Vec3 _faceNormal(MeshFace face) {
    var x = 0.0;
    var y = 0.0;
    var z = 0.0;
    for (var index = 0; index < face.vertices.length; index++) {
      final current = vertices[face.vertices[index]].position;
      final next =
          vertices[face.vertices[(index + 1) % face.vertices.length]].position;
      x += (current.y - next.y) * (current.z + next.z);
      y += (current.z - next.z) * (current.x + next.x);
      z += (current.x - next.x) * (current.y + next.y);
    }
    final length = math.sqrt(x * x + y * y + z * z);
    if (length > 1e-12) {
      return Vec3(x / length, y / length, z / length);
    }
    return const Vec3(0, 0, 1);
  }

  List<Offset> _faceLocalCoordinates(MeshFace face) {
    final origin = vertices[face.vertices.first].position;
    final normal = _faceNormal(face);
    var bestEdge = const Vec3(1, 0, 0);
    var bestLengthSquared = 0.0;
    for (var index = 0; index < face.vertices.length; index++) {
      final current = vertices[face.vertices[index]].position;
      final next =
          vertices[face.vertices[(index + 1) % face.vertices.length]].position;
      final edge = _subtract(next, current);
      final lengthSquared = _dot(edge, edge);
      if (lengthSquared > bestLengthSquared) {
        bestLengthSquared = lengthSquared;
        bestEdge = edge;
      }
    }
    final edgeLength = math.sqrt(bestLengthSquared);
    if (edgeLength <= 1e-12) {
      return List.filled(face.vertices.length, Offset.zero);
    }
    final axisX = _scale(bestEdge, 1 / edgeLength);
    var axisY = _cross(normal, axisX);
    var axisYLength = math.sqrt(_dot(axisY, axisY));
    if (axisYLength <= 1e-12) {
      final reference =
          axisX.x.abs() < 0.8 ? const Vec3(1, 0, 0) : const Vec3(0, 1, 0);
      axisY = _subtract(reference, _scale(axisX, _dot(reference, axisX)));
      axisYLength = math.sqrt(_dot(axisY, axisY));
    }
    final normalizedY = _scale(axisY, 1 / axisYLength);
    return [
      for (final vertexIndex in face.vertices)
        Offset(
          _dot(_subtract(vertices[vertexIndex].position, origin), axisX),
          _dot(_subtract(vertices[vertexIndex].position, origin), normalizedY),
        ),
    ];
  }

  List<Offset>? _unfoldFaceAcrossEdge(
    int parentIndex,
    int childIndex,
    int edgeA,
    int edgeB,
    List<Offset> parentUvs,
    List<Offset> childLocalUvs,
  ) {
    final parentFace = faces[parentIndex];
    final childFace = faces[childIndex];
    final parentA = parentFace.vertices.indexOf(edgeA);
    final parentB = parentFace.vertices.indexOf(edgeB);
    final childA = childFace.vertices.indexOf(edgeA);
    final childB = childFace.vertices.indexOf(edgeB);
    if (parentA < 0 || parentB < 0 || childA < 0 || childB < 0) return null;

    final sourceA = childLocalUvs[childA];
    final sourceB = childLocalUvs[childB];
    final targetA = parentUvs[parentA];
    final targetB = parentUvs[parentB];
    final sourceDx = sourceB.dx - sourceA.dx;
    final sourceDy = sourceB.dy - sourceA.dy;
    final targetDx = targetB.dx - targetA.dx;
    final targetDy = targetB.dy - targetA.dy;
    final sourceLength = math.sqrt(sourceDx * sourceDx + sourceDy * sourceDy);
    final targetLength = math.sqrt(targetDx * targetDx + targetDy * targetDy);
    if (sourceLength <= 1e-12 || targetLength <= 1e-12) return null;
    final sourceUnit = Offset(sourceDx / sourceLength, sourceDy / sourceLength);
    final targetUnit = Offset(targetDx / targetLength, targetDy / targetLength);
    final parentCenter = _average(parentUvs);
    final childCenter = _average(childLocalUvs);
    final parentSide = _cross2(
      Offset(targetDx, targetDy),
      parentCenter - targetA,
    );
    final childSide = _cross2(
      Offset(sourceDx, sourceDy),
      childCenter - sourceA,
    );
    final reflection = parentSide * childSide >= 0 ? -1.0 : 1.0;

    return [
      for (final point in childLocalUvs)
        _unfoldPoint(
          point,
          sourceA,
          targetA,
          sourceUnit,
          targetUnit,
          reflection,
        ),
    ];
  }

  Offset _unfoldPoint(
    Offset point,
    Offset sourceOrigin,
    Offset targetOrigin,
    Offset sourceAxis,
    Offset targetAxis,
    double reflection,
  ) {
    final relative = point - sourceOrigin;
    final along = relative.dx * sourceAxis.dx + relative.dy * sourceAxis.dy;
    final across = _cross2(sourceAxis, relative) * reflection;
    return Offset(
      targetOrigin.dx + targetAxis.dx * along - targetAxis.dy * across,
      targetOrigin.dy + targetAxis.dy * along + targetAxis.dx * across,
    );
  }

  _UvChart _createUvChart(Map<int, List<Offset>> faceUvs) {
    final points = faceUvs.values.expand((uvs) => uvs);
    final minX = points.map((point) => point.dx).reduce(math.min);
    final maxX = points.map((point) => point.dx).reduce(math.max);
    final minY = points.map((point) => point.dy).reduce(math.min);
    final maxY = points.map((point) => point.dy).reduce(math.max);
    return _UvChart(faceUvs, minX, minY, maxX, maxY);
  }

  List<_UvChartPlacement>? _packUvCharts(List<_UvChart> charts) {
    final gap = math.min(0.012, 0.45 / math.sqrt(charts.length));
    final sortOrders = <int Function(_UvChart, _UvChart)>[
      (first, second) => _chartArea(second).compareTo(_chartArea(first)),
      (first, second) => second.height.compareTo(first.height),
      (first, second) => second.width.compareTo(first.width),
    ];
    final orderedCharts = [
      for (final compare in sortOrders) [...charts]..sort(compare),
    ];
    var low = 0.0;
    var high = 1.0;
    List<_UvChartPlacement>? best;
    for (var iteration = 0; iteration < 22; iteration++) {
      final scale = (low + high) / 2;
      List<_UvChartPlacement>? candidate;
      for (final ordered in orderedCharts) {
        candidate = _tryPackUvCharts(ordered, scale, gap);
        if (candidate != null) break;
      }
      if (candidate == null) {
        high = scale;
      } else {
        low = scale;
        best = candidate;
      }
    }
    return best;
  }

  List<_UvChartPlacement>? _tryPackUvCharts(
    List<_UvChart> charts,
    double scale,
    double gap,
  ) {
    var x = gap;
    var y = gap;
    var rowHeight = 0.0;
    final placements = <_UvChartPlacement>[];
    for (final chart in charts) {
      final width = chart.width * scale + gap * 2;
      final height = chart.height * scale + gap * 2;
      if (width > 1 || height > 1) return null;
      if (x + width > 1) {
        y += rowHeight;
        x = gap;
        rowHeight = 0;
      }
      if (y + height > 1) return null;
      placements.add(
        _UvChartPlacement(chart, x + gap, y + gap, scale),
      );
      x += width;
      rowHeight = math.max(rowHeight, height);
    }
    return placements;
  }

  double _chartArea(_UvChart chart) => chart.width * chart.height;

  Offset _average(List<Offset> points) {
    if (points.isEmpty) return Offset.zero;
    return Offset(
      points.fold<double>(0, (sum, point) => sum + point.dx) / points.length,
      points.fold<double>(0, (sum, point) => sum + point.dy) / points.length,
    );
  }

  double _cross2(Offset first, Offset second) =>
      first.dx * second.dy - first.dy * second.dx;

  double _dot(Vec3 first, Vec3 second) =>
      first.x * second.x + first.y * second.y + first.z * second.z;

  Vec3 _subtract(Vec3 first, Vec3 second) =>
      Vec3(first.x - second.x, first.y - second.y, first.z - second.z);

  Vec3 _scale(Vec3 value, double factor) =>
      Vec3(value.x * factor, value.y * factor, value.z * factor);

  Vec3 _cross(Vec3 first, Vec3 second) => Vec3(
        first.y * second.z - first.z * second.y,
        first.z * second.x - first.x * second.z,
        first.x * second.y - first.y * second.x,
      );

  bool projectUvFromView(
    Iterable<int> selectedFaces,
    Vec3 right,
    Vec3 up,
  ) {
    final selection = selectedFaces.toSet().toList()..sort();
    if (selection.isEmpty ||
        selection.any((index) => index < 0 || index >= faces.length)) {
      return false;
    }
    final positions = selection
        .expand((faceIndex) => faces[faceIndex].vertices)
        .map((vertexIndex) => vertices[vertexIndex].position)
        .toList();
    double dot(Vec3 point, Vec3 axis) =>
        point.x * axis.x + point.y * axis.y + point.z * axis.z;
    final projected = positions
        .map((point) => Offset(dot(point, right), dot(point, up)))
        .toList();
    final minX = projected.map((point) => point.dx).reduce(math.min);
    final maxX = projected.map((point) => point.dx).reduce(math.max);
    final minY = projected.map((point) => point.dy).reduce(math.min);
    final maxY = projected.map((point) => point.dy).reduce(math.max);
    final spanX = maxX - minX;
    final spanY = maxY - minY;
    if (spanX < 1e-8 && spanY < 1e-8) return false;
    const padding = 0.05;
    final scale = (1 - 2 * padding) / math.max(math.max(spanX, spanY), 1e-8);
    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;
    for (final faceIndex in selection) {
      final face = faces[faceIndex];
      face.uv
        ..clear()
        ..addAll(face.vertices.map((vertexIndex) {
          final point = vertices[vertexIndex].position;
          return Offset(
            (0.5 + (dot(point, right) - centerX) * scale)
                .clamp(padding, 1 - padding)
                .toDouble(),
            (0.5 + (dot(point, up) - centerY) * scale)
                .clamp(padding, 1 - padding)
                .toDouble(),
          );
        }));
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
