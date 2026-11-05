import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'mesh.dart';

const int rvFlagQuad = 0x0001;
const int rvFlagDoubleSided = 0x0002;
const int rvFlagTranslucent = 0x0004;
const int rvFlagMirror = 0x0080;
const int rvFlagAddBlending = 0x0100;
const int rvFlagTextureAnimation = 0x0200;
const int rvFlagNoEnvMap = 0x0400;
const int rvFlagEnvMap = 0x0800;
const int rvFlagInvisible = 0x2000;

class RvImportedMesh {
  const RvImportedMesh({
    required this.name,
    required this.mesh,
    required this.coordinateScale,
    required this.coordinateOrigin,
  });

  final String name;
  final MeshModel mesh;
  final double coordinateScale;
  final Vec3 coordinateOrigin;
}

class RvImportResult {
  const RvImportResult({
    required this.meshes,
    required this.isWorld,
    this.lodCount = 1,
    this.environmentColors = const <int>[],
    this.textureAnimations = const [],
  });

  final List<RvImportedMesh> meshes;
  final bool isWorld;
  final int lodCount;
  final List<int> environmentColors;
  final List<Uint8List> textureAnimations;
}

class RvExportMesh {
  const RvExportMesh({
    required this.mesh,
    this.coordinateScale = 0.01,
    this.coordinateOrigin = const Vec3(0, 0, 0),
  });

  final MeshModel mesh;
  final double coordinateScale;
  final Vec3 coordinateOrigin;
}

class _DecodedGeometry {
  const _DecodedGeometry(this.mesh, this.endOffset);

  final MeshModel mesh;
  final int endOffset;
}

class _FaceReference {
  const _FaceReference(this.meshIndex, this.faceIndex);

  final int meshIndex;
  final int faceIndex;
}

class RvModelIo {
  static const int maxFaceCount = 100000;
  static const int _faceRecordSize = 60;
  static const int _vertexRecordSize = 24;
  static const int _maxMeshCount = 65535;
  static const double _prmScale = 0.01;

  static Future<RvImportResult> readPrm(String path) async {
    final bytes = await File(path).readAsBytes();
    final name = _basename(path);
    return Isolate.run(() => decodePrm(bytes, name: name));
  }

  static Future<RvImportResult> readWorld(String path) async {
    final bytes = await File(path).readAsBytes();
    final name = _basename(path);
    return Isolate.run(() => decodeWorld(bytes, name: name));
  }

  static RvImportResult decodePrm(Uint8List bytes, {String name = 'Model'}) {
    final data = ByteData.sublistView(bytes);
    final lods = <MeshModel>[];
    var offset = 0;
    var totalFaces = 0;
    while (offset < data.lengthInBytes) {
      if (data.lengthInBytes - offset < 4) {
        throw const FormatException('The PRM file ends inside a mesh header.');
      }
      final geometry = _readGeometry(data, offset);
      totalFaces += geometry.mesh.faces.length;
      if (totalFaces > maxFaceCount * 8) {
        throw const FormatException(
            'The PRM file contains too many LOD faces.');
      }
      lods.add(geometry.mesh);
      offset = geometry.endOffset;
    }
    if (lods.isEmpty || lods.first.faces.isEmpty) {
      throw const FormatException('This PRM file does not contain a mesh.');
    }
    final first = lods.first;
    final (center, centered) = _centerMeshes([first], _prmScale);
    return RvImportResult(
      meshes: [
        RvImportedMesh(
          name: name,
          mesh: centered.single,
          coordinateScale: _prmScale,
          coordinateOrigin: center,
        ),
      ],
      isWorld: false,
      lodCount: lods.length,
    );
  }

  static RvImportResult decodeWorld(Uint8List bytes, {String name = 'World'}) {
    final data = ByteData.sublistView(bytes);
    var offset = 0;
    _require(data, offset, 4, 'world mesh count');
    final meshCount = data.getInt32(offset, Endian.little);
    offset += 4;
    if (meshCount <= 0 || meshCount > _maxMeshCount) {
      throw FormatException('Invalid world mesh count: $meshCount.');
    }

    final rawMeshes = <MeshModel>[];
    var totalFaces = 0;
    final environmentFaces = <_FaceReference>[];
    for (var meshIndex = 0; meshIndex < meshCount; meshIndex++) {
      _require(data, offset, 44, 'world mesh header');
      final geometry = _readGeometry(data, offset + 40);
      final faceCount = data.getUint16(offset + 40, Endian.little);
      totalFaces += faceCount;
      if (totalFaces > maxFaceCount) {
        throw const FormatException(
          'The world has more than $maxFaceCount faces; Blunder supports up to $maxFaceCount.',
        );
      }
      for (var faceIndex = 0;
          faceIndex < geometry.mesh.faces.length;
          faceIndex++) {
        if ((geometry.mesh.faces[faceIndex].rvType & rvFlagEnvMap) != 0) {
          environmentFaces.add(_FaceReference(meshIndex, faceIndex));
        }
      }
      rawMeshes.add(geometry.mesh);
      offset = geometry.endOffset;
    }

    _require(data, offset, 4, 'world big-cube count');
    final bigCubeCount = data.getInt32(offset, Endian.little);
    offset += 4;
    if (bigCubeCount < 0 || bigCubeCount > _maxMeshCount) {
      throw FormatException('Invalid world big-cube count: $bigCubeCount.');
    }
    for (var index = 0; index < bigCubeCount; index++) {
      _require(data, offset, 20, 'world big-cube');
      final meshCountInCube = data.getInt32(offset + 16, Endian.little);
      if (meshCountInCube < 0 || meshCountInCube > meshCount) {
        throw FormatException('Invalid mesh count in world big-cube $index.');
      }
      final size = 20 + meshCountInCube * 4;
      _require(data, offset, size, 'world big-cube indices');
      for (var item = 0; item < meshCountInCube; item++) {
        final meshIndex = data.getInt32(offset + 20 + item * 4, Endian.little);
        if (meshIndex < 0 || meshIndex >= meshCount) {
          throw FormatException('Invalid mesh index in world big-cube $index.');
        }
      }
      offset += size;
    }

    _require(data, offset, 4, 'world texture-animation count');
    final animationCount = data.getInt32(offset, Endian.little);
    offset += 4;
    if (animationCount < 0 || animationCount > 65535) {
      throw FormatException(
          'Invalid world texture-animation count: $animationCount.');
    }
    final animations = <Uint8List>[];
    for (var index = 0; index < animationCount; index++) {
      _require(data, offset, 4, 'texture-animation frame count');
      final frameCount = data.getUint32(offset, Endian.little);
      if (frameCount > 1000000) {
        throw const FormatException('A texture animation has too many frames.');
      }
      final length = 4 + frameCount * 40;
      _require(data, offset, length, 'texture-animation frames');
      animations.add(Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes + offset, length),
      ));
      offset += length;
    }

    final environmentBytes = environmentFaces.length * 4;
    _require(data, offset, environmentBytes, 'world environment colors');
    final environmentColors = Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes + offset, environmentBytes),
    );
    for (var index = 0; index < environmentFaces.length; index++) {
      final faceRef = environmentFaces[index];
      final face = rawMeshes[faceRef.meshIndex].faces[faceRef.faceIndex];
      face.rvEnvironmentColor = ByteData.sublistView(environmentColors)
          .getUint32(index * 4, Endian.little);
    }
    offset += environmentBytes;
    if (offset != data.lengthInBytes) {
      throw FormatException(
        'The world file has ${data.lengthInBytes - offset} unrecognized trailing bytes.',
      );
    }

    final sourceScale = _worldScale(rawMeshes);
    final (origin, centeredMeshes) = _centerMeshes(rawMeshes, sourceScale);
    return RvImportResult(
      meshes: [
        for (var index = 0; index < centeredMeshes.length; index++)
          RvImportedMesh(
            name: '${name}_${(index + 1).toString().padLeft(3, '0')}',
            mesh: centeredMeshes[index],
            coordinateScale: sourceScale,
            coordinateOrigin: origin,
          ),
      ],
      isWorld: true,
      environmentColors: environmentColors,
      textureAnimations: animations,
    );
  }

  static _DecodedGeometry _readGeometry(ByteData data, int offset) {
    _require(data, offset, 4, 'mesh counts');
    final faceCount = data.getUint16(offset, Endian.little);
    final vertexCount = data.getUint16(offset + 2, Endian.little);
    if (faceCount > maxFaceCount) {
      throw const FormatException('A model has more than $maxFaceCount faces.');
    }
    final facesOffset = offset + 4;
    final verticesOffset = facesOffset + faceCount * _faceRecordSize;
    final endOffset = verticesOffset + vertexCount * _vertexRecordSize;
    _require(data, offset, endOffset - offset, 'mesh geometry');

    final positions = <Vec3>[];
    for (var index = 0; index < vertexCount; index++) {
      final vertexOffset = verticesOffset + index * _vertexRecordSize;
      positions.add(
        Vec3(
          data.getFloat32(vertexOffset, Endian.little),
          data.getFloat32(vertexOffset + 4, Endian.little),
          data.getFloat32(vertexOffset + 8, Endian.little),
        ),
      );
    }

    final faces = <MeshFace>[];
    for (var index = 0; index < faceCount; index++) {
      final faceOffset = facesOffset + index * _faceRecordSize;
      final type = data.getUint16(faceOffset, Endian.little);
      final texture = data.getInt16(faceOffset + 2, Endian.little);
      final cornerCount = (type & rvFlagQuad) != 0 ? 4 : 3;
      final indices = [
        for (var corner = 0; corner < 4; corner++)
          data.getUint16(faceOffset + 4 + corner * 2, Endian.little),
      ];
      final vertices = [
        for (var corner = cornerCount - 1; corner >= 0; corner--)
          indices[corner],
      ];
      if (vertices.any((vertex) => vertex >= vertexCount)) {
        throw FormatException('Face ${index + 1} has an invalid vertex index.');
      }
      final colors = [
        for (var corner = 0; corner < 4; corner++)
          data.getUint32(faceOffset + 12 + corner * 4, Endian.little),
      ];
      final sourceUv = [
        for (var corner = 0; corner < 4; corner++)
          Offset(
            data.getFloat32(faceOffset + 28 + corner * 8, Endian.little),
            data.getFloat32(faceOffset + 32 + corner * 8, Endian.little),
          ),
      ];
      if (sourceUv.any((uv) => !uv.dx.isFinite || !uv.dy.isFinite)) {
        throw FormatException(
            'Face ${index + 1} has invalid texture coordinates.');
      }
      faces.add(
        MeshFace(
          vertices,
          [
            for (var corner = cornerCount - 1; corner >= 0; corner--)
              Offset(sourceUv[corner].dx, 1 - sourceUv[corner].dy),
          ],
          rvType: type,
          rvTextureIndex: texture,
          rvColors: [
            for (var corner = cornerCount - 1; corner >= 0; corner--)
              colors[corner],
          ],
          rvExtraColor: cornerCount == 3 ? colors[3] : null,
          rvExtraUv: cornerCount == 3 ? sourceUv[3] : null,
        ),
      );
    }
    return _DecodedGeometry(
      MeshModel.fromData(positions, faces),
      endOffset,
    );
  }

  static (Vec3, List<MeshModel>) _centerMeshes(
    List<MeshModel> meshes,
    double scale,
  ) {
    final positions = meshes
        .expand((mesh) => mesh.vertices)
        .map((vertex) => _sourceToApp(vertex.position, scale))
        .toList();
    if (positions.isEmpty) {
      throw const FormatException('The RV file does not contain any vertices.');
    }
    final origin = Vec3(
      (positions.map((point) => point.x).reduce(math.min) +
              positions.map((point) => point.x).reduce(math.max)) /
          2,
      (positions.map((point) => point.y).reduce(math.min) +
              positions.map((point) => point.y).reduce(math.max)) /
          2,
      (positions.map((point) => point.z).reduce(math.min) +
              positions.map((point) => point.z).reduce(math.max)) /
          2,
    );
    return (
      origin,
      [
        for (final mesh in meshes)
          MeshModel.fromData(
            mesh.vertices.map(
              (vertex) => _subtract(
                _sourceToApp(vertex.position, scale),
                origin,
              ),
            ),
            mesh.faces,
            smoothShading: mesh.smoothShading,
          ),
      ],
    );
  }

  static double _worldScale(List<MeshModel> meshes) {
    final positions = meshes.expand((mesh) => mesh.vertices).map(
          (vertex) => vertex.position,
        );
    final points = positions.toList();
    if (points.isEmpty) return _prmScale;
    final spans = [
      points.map((point) => point.x).reduce(math.max) -
          points.map((point) => point.x).reduce(math.min),
      points.map((point) => point.y).reduce(math.max) -
          points.map((point) => point.y).reduce(math.min),
      points.map((point) => point.z).reduce(math.max) -
          points.map((point) => point.z).reduce(math.min),
    ];
    final extent = spans.reduce(math.max);
    return extent <= 0 ? _prmScale : math.min(_prmScale, 14 / extent);
  }

  static Vec3 _sourceToApp(Vec3 point, double scale) =>
      Vec3(point.x * scale, point.z * scale, -point.y * scale);

  static Vec3 _appToSource(
    Vec3 point,
    double scale,
    Vec3 origin,
  ) =>
      Vec3(
        (point.x + origin.x) / scale,
        -(point.z + origin.z) / scale,
        (point.y + origin.y) / scale,
      );

  static Vec3 _subtract(Vec3 first, Vec3 second) =>
      Vec3(first.x - second.x, first.y - second.y, first.z - second.z);

  static Uint8List encodePrm(Iterable<RvExportMesh> sourceMeshes) {
    final meshes = sourceMeshes.toList();
    final positions = <Vec3>[];
    final faces = <MeshFace>[];
    for (final source in meshes) {
      if (positions.length + source.mesh.vertices.length > 65535) {
        throw const FormatException('PRM supports up to 65535 vertices.');
      }
      final vertexOffset = positions.length;
      positions.addAll(
        source.mesh.vertices.map(
          (vertex) => _appToSource(
            vertex.position,
            source.coordinateScale,
            source.coordinateOrigin,
          ),
        ),
      );
      faces.addAll(
        source.mesh.faces.map(
          (face) => MeshFace.copyOf(
            face,
            vertices:
                face.vertices.map((index) => index + vertexOffset).toList(),
          ),
        ),
      );
    }
    final polygons = _triangulate(faces);
    if (polygons.length > maxFaceCount) {
      throw const FormatException('Blunder supports up to 100000 faces.');
    }
    if (positions.isEmpty || polygons.isEmpty) {
      throw const FormatException('There is no mesh geometry to export.');
    }
    if (positions.length > 65535) {
      throw const FormatException('PRM supports up to 65535 vertices.');
    }
    final output = BytesBuilder(copy: false);
    final header = ByteData(4)
      ..setUint16(0, polygons.length, Endian.little)
      ..setUint16(2, positions.length, Endian.little);
    output.add(header.buffer.asUint8List());
    _writeFaces(output, polygons);
    _writeVertices(output, positions, polygons);
    return output.takeBytes();
  }

  static Uint8List encodeWorld(
    Iterable<RvExportMesh> sourceMeshes, {
    List<int> environmentColors = const <int>[],
    List<Uint8List> textureAnimations = const [],
  }) {
    final meshes = sourceMeshes.toList();
    final facesByMesh = [
      for (final source in meshes) _triangulate(source.mesh.faces),
    ];
    final totalFaces = facesByMesh.fold<int>(
      0,
      (count, faces) => count + faces.length,
    );
    if (totalFaces > maxFaceCount) {
      throw const FormatException('Blunder supports up to 100000 faces.');
    }
    if (meshes.isEmpty) {
      throw const FormatException('There are no meshes to export.');
    }
    if (meshes.length > _maxMeshCount) {
      throw const FormatException('The world contains too many meshes.');
    }
    final output = BytesBuilder(copy: false);
    _appendInt32(output, meshes.length);
    for (var index = 0; index < meshes.length; index++) {
      final source = meshes[index];
      final positions = source.mesh.vertices
          .map(
            (vertex) => _appToSource(
              vertex.position,
              source.coordinateScale,
              source.coordinateOrigin,
            ),
          )
          .toList();
      if (positions.length > 65535) {
        throw const FormatException(
            'Each world mesh supports up to 65535 vertices.');
      }
      if (facesByMesh[index].length > 65535) {
        throw const FormatException(
            'Each world mesh supports up to 65535 faces.');
      }
      _writeBounds(output, positions);
      _appendUint16(output, facesByMesh[index].length);
      _appendUint16(output, positions.length);
      _writeFaces(output, facesByMesh[index]);
      _writeVertices(output, positions, facesByMesh[index]);
    }

    _appendInt32(output, 1);
    final allPositions = <Vec3>[];
    for (var meshIndex = 0; meshIndex < meshes.length; meshIndex++) {
      final source = meshes[meshIndex];
      allPositions.addAll(
        source.mesh.vertices.map(
          (vertex) => _appToSource(
            vertex.position,
            source.coordinateScale,
            source.coordinateOrigin,
          ),
        ),
      );
    }
    final worldBounds = _bounds(allPositions);
    final cubeCenter = Vec3(
      (worldBounds.$1.x + worldBounds.$2.x) / 2,
      (worldBounds.$1.y + worldBounds.$2.y) / 2,
      (worldBounds.$1.z + worldBounds.$2.z) / 2,
    );
    final radius = allPositions
        .map((point) => _distance(point, cubeCenter))
        .fold<double>(0, (a, b) => math.max(a, b));
    _appendVector(output, cubeCenter);
    _appendFloat(output, radius);
    _appendInt32(output, meshes.length);
    for (var index = 0; index < meshes.length; index++) {
      _appendInt32(output, index);
    }

    _appendInt32(output, textureAnimations.length);
    for (final animation in textureAnimations) {
      if (animation.length < 4) {
        throw const FormatException('A world texture animation is incomplete.');
      }
      output.add(animation);
    }
    var envIndex = 0;
    for (final faces in facesByMesh) {
      for (final face in faces) {
        if ((face.rvType & rvFlagEnvMap) == 0) continue;
        if (face.rvEnvironmentColor != null) {
          _appendUint32(output, face.rvEnvironmentColor!);
        } else if (envIndex * 4 + 4 <= environmentColors.length) {
          output.add(environmentColors.sublist(envIndex * 4, envIndex * 4 + 4));
        } else {
          _appendUint32(output, 0x00ffffff);
        }
        envIndex++;
      }
    }
    return output.takeBytes();
  }

  static List<MeshFace> _triangulate(Iterable<MeshFace> sourceFaces) {
    final result = <MeshFace>[];
    for (final face in sourceFaces) {
      if (face.vertices.length <= 4) {
        result.add(face);
        continue;
      }
      for (var corner = 1; corner < face.vertices.length - 1; corner++) {
        final corners = [0, corner, corner + 1];
        result.add(
          MeshFace.copyOf(
            face,
            vertices: corners.map((index) => face.vertices[index]).toList(),
            uv: corners.map((index) => face.uv[index]).toList(),
            rvColors: corners
                .map((index) => index < face.rvColors.length
                    ? face.rvColors[index]
                    : 0x00ffffff)
                .toList(),
            rvType: face.rvType & ~rvFlagQuad,
          ),
        );
      }
    }
    return result;
  }

  static void _writeFaces(BytesBuilder output, List<MeshFace> faces) {
    for (final face in faces) {
      final cornerCount = face.vertices.length;
      if (cornerCount != 3 && cornerCount != 4) {
        throw const FormatException(
            'RV faces must have three or four corners.');
      }
      final record = ByteData(_faceRecordSize);
      final type =
          (face.rvType & ~rvFlagQuad) | (cornerCount == 4 ? rvFlagQuad : 0);
      record
        ..setUint16(0, type & 0xffff, Endian.little)
        ..setInt16(
          2,
          face.rvTextureIndex.clamp(-32768, 32767).toInt(),
          Endian.little,
        );
      final fileVertices = face.vertices.reversed.toList();
      for (var corner = 0; corner < 4; corner++) {
        record.setUint16(
          4 + corner * 2,
          corner < fileVertices.length ? fileVertices[corner] : 0,
          Endian.little,
        );
      }
      final fileColors = face.rvColors.reversed.toList();
      if (cornerCount == 3) {
        fileColors.add(face.rvExtraColor ?? 0x00ffffff);
      }
      while (fileColors.length < 4) {
        fileColors.add(0x00ffffff);
      }
      for (var corner = 0; corner < 4; corner++) {
        record.setUint32(12 + corner * 4, fileColors[corner], Endian.little);
      }
      final fileUvs = face.uv.reversed.toList();
      if (cornerCount == 3) fileUvs.add(face.rvExtraUv ?? Offset.zero);
      while (fileUvs.length < 4) {
        fileUvs.add(Offset.zero);
      }
      for (var corner = 0; corner < 4; corner++) {
        record
          ..setFloat32(28 + corner * 8, fileUvs[corner].dx, Endian.little)
          ..setFloat32(32 + corner * 8, 1 - fileUvs[corner].dy, Endian.little);
      }
      output.add(record.buffer.asUint8List());
    }
  }

  static void _writeVertices(
    BytesBuilder output,
    List<Vec3> positions,
    List<MeshFace> faces,
  ) {
    final normals = List<Vec3>.filled(
      positions.length,
      const Vec3(0, 0, 0),
    );
    for (final face in faces) {
      final indices = face.vertices.reversed.toList();
      final first = positions[indices[0]];
      final second = positions[indices[1]];
      final third = positions[indices[2]];
      final normal = _cross(
        Vec3(
          second.x - first.x,
          second.y - first.y,
          second.z - first.z,
        ),
        Vec3(
          third.x - first.x,
          third.y - first.y,
          third.z - first.z,
        ),
      );
      for (final index in indices) {
        final sum = normals[index];
        normals[index] = Vec3(
          sum.x + normal.x,
          sum.y + normal.y,
          sum.z + normal.z,
        );
      }
    }
    for (var index = 0; index < positions.length; index++) {
      final point = positions[index];
      final normal = _normalized(normals[index]);
      _appendVector(output, point);
      _appendVector(output, normal);
    }
  }

  static void _writeBounds(BytesBuilder output, List<Vec3> positions) {
    if (positions.isEmpty) {
      for (var index = 0; index < 10; index++) {
        _appendFloat(output, 0);
      }
      return;
    }
    final bounds = _bounds(positions);
    final center = Vec3(
      (bounds.$1.x + bounds.$2.x) / 2,
      (bounds.$1.y + bounds.$2.y) / 2,
      (bounds.$1.z + bounds.$2.z) / 2,
    );
    final radius = positions
        .map((point) => _distance(point, center))
        .fold<double>(0, (a, b) => math.max(a, b));
    _appendVector(output, center);
    _appendFloat(output, radius);
    for (final values in [
      [bounds.$1.x, bounds.$2.x],
      [bounds.$1.y, bounds.$2.y],
      [bounds.$1.z, bounds.$2.z],
    ]) {
      for (final value in values) {
        _appendFloat(output, value);
      }
    }
  }

  static (Vec3, Vec3) _bounds(List<Vec3> positions) => (
        Vec3(
          positions.map((point) => point.x).reduce(math.min),
          positions.map((point) => point.y).reduce(math.min),
          positions.map((point) => point.z).reduce(math.min),
        ),
        Vec3(
          positions.map((point) => point.x).reduce(math.max),
          positions.map((point) => point.y).reduce(math.max),
          positions.map((point) => point.z).reduce(math.max),
        ),
      );

  static Vec3 _cross(Vec3 first, Vec3 second) => Vec3(
        first.y * second.z - first.z * second.y,
        first.z * second.x - first.x * second.z,
        first.x * second.y - first.y * second.x,
      );

  static Vec3 _normalized(Vec3 point) {
    final length =
        math.sqrt(point.x * point.x + point.y * point.y + point.z * point.z);
    if (length < 1e-12) return const Vec3(0, 1, 0);
    return Vec3(point.x / length, point.y / length, point.z / length);
  }

  static double _distance(Vec3 first, Vec3 second) {
    final dx = first.x - second.x;
    final dy = first.y - second.y;
    final dz = first.z - second.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  static void _appendVector(BytesBuilder output, Vec3 point) {
    _appendFloat(output, point.x);
    _appendFloat(output, point.y);
    _appendFloat(output, point.z);
  }

  static void _appendFloat(BytesBuilder output, double value) {
    final bytes = ByteData(4)..setFloat32(0, value, Endian.little);
    output.add(bytes.buffer.asUint8List());
  }

  static void _appendUint16(BytesBuilder output, int value) {
    final bytes = ByteData(2)..setUint16(0, value, Endian.little);
    output.add(bytes.buffer.asUint8List());
  }

  static void _appendUint32(BytesBuilder output, int value) {
    final bytes = ByteData(4)..setUint32(0, value, Endian.little);
    output.add(bytes.buffer.asUint8List());
  }

  static void _appendInt32(BytesBuilder output, int value) {
    final bytes = ByteData(4)..setInt32(0, value, Endian.little);
    output.add(bytes.buffer.asUint8List());
  }

  static void _require(ByteData data, int offset, int length, String field) {
    if (offset < 0 ||
        length < 0 ||
        offset > data.lengthInBytes ||
        length > data.lengthInBytes - offset) {
      throw FormatException('The RV file is truncated at $field.');
    }
  }

  static String _basename(String path) {
    final name = File(path).uri.pathSegments.last;
    return name.replaceFirst(RegExp(r'\.[^.]+$'), '');
  }
}
