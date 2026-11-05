import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'dart:ui' show Offset;

import 'mesh.dart';

class ModelMeshData {
  const ModelMeshData({
    required this.name,
    required this.mesh,
    this.texturePath,
    this.groupName,
    this.rvCoordinateScale,
    this.rvCoordinateOrigin,
    this.rvTextureAnimations = const [],
    this.rvTexturePaths = const {},
  });

  final String name;
  final MeshModel mesh;
  final String? texturePath;
  final String? groupName;
  final double? rvCoordinateScale;
  final Vec3? rvCoordinateOrigin;
  final List<Uint8List> rvTextureAnimations;
  final Map<int, String> rvTexturePaths;
}

class ModelIo {
  static const int maxFaceCount = 100000;

  static void _validateFaceCount(Iterable<ModelMeshData> objects) {
    final count = objects.fold<int>(
      0,
      (total, object) => total + object.mesh.faces.length,
    );
    if (count > maxFaceCount) {
      throw FormatException(
        'The scene has $count faces; Blunder supports up to $maxFaceCount.',
      );
    }
  }

  static String encodePky(Iterable<ModelMeshData> objects) {
    final objectList = objects.toList();
    _validateFaceCount(objectList);
    final output = StringBuffer(
      '# Blunder PKY 1.0 (Wavefront OBJ-compatible geometry)\n',
    );
    var vertexOffset = 1;
    var uvOffset = 1;
    for (final object in objectList) {
      final name = object.name.trim().replaceAll(RegExp(r'[\r\n]+'), '_');
      output.writeln('o ${name.isEmpty ? 'Mesh' : name}');
      final texturePath = object.texturePath;
      if (texturePath != null && texturePath.isNotEmpty) {
        output.writeln(
          '# blunder_texture_base64='
          '${base64Url.encode(utf8.encode(texturePath))}',
        );
      }
      final groupName = object.groupName;
      if (groupName != null && groupName.isNotEmpty) {
        output.writeln(
          '# blunder_group_base64='
          '${base64Url.encode(utf8.encode(groupName))}',
        );
      }
      if (object.mesh.smoothShading) {
        output.writeln('# blunder_smooth_shading=1');
      }
      if (object.rvCoordinateScale != null) {
        output.writeln(
          '# blunder_rv_metadata_base64=${base64Url.encode(utf8.encode(jsonEncode({
                'scale': object.rvCoordinateScale,
                'origin': [
                  object.rvCoordinateOrigin?.x ?? 0,
                  object.rvCoordinateOrigin?.y ?? 0,
                  object.rvCoordinateOrigin?.z ?? 0,
                ],
                'animations': [
                  for (final animation in object.rvTextureAnimations)
                    base64Url.encode(animation),
                ],
                'textures': {
                  for (final entry in object.rvTexturePaths.entries)
                    entry.key.toString(): entry.value,
                },
              })))}',
        );
      }
      for (final vertex in object.mesh.vertices) {
        final position = vertex.position;
        output.writeln('v ${_number(position.x)} '
            '${_number(position.y)} ${_number(position.z)}');
      }
      for (final face in object.mesh.faces) {
        for (final uv in face.uv) {
          output.writeln('vt ${_number(uv.dx)} ${_number(uv.dy)}');
        }
      }
      var faceUvOffset = uvOffset;
      for (final face in object.mesh.faces) {
        if (object.rvCoordinateScale != null) {
          output.writeln(
            '# blunder_rv_face_base64=${base64Url.encode(utf8.encode(jsonEncode({
                  'type': face.rvType,
                  'texture': face.rvTextureIndex,
                  'colors': face.rvColors,
                  'extraColor': face.rvExtraColor,
                  'extraUv': face.rvExtraUv == null
                      ? null
                      : [face.rvExtraUv!.dx, face.rvExtraUv!.dy],
                  'environmentColor': face.rvEnvironmentColor,
                })))}',
          );
        }
        final refs = <String>[];
        for (var corner = 0; corner < face.vertices.length; corner++) {
          refs.add(
            '${face.vertices[corner] + vertexOffset}/'
            '${faceUvOffset + corner}',
          );
        }
        output.writeln('f ${refs.join(' ')}');
        faceUvOffset += face.uv.length;
      }
      vertexOffset += object.mesh.vertices.length;
      uvOffset += object.mesh.faces.fold<int>(
        0,
        (count, face) => count + face.uv.length,
      );
    }
    return output.toString();
  }

  static List<ModelMeshData> decodePky(String content) {
    final positions = <Vec3>[];
    final textureCoordinates = <Offset>[];
    final builders = <_ObjectBuilder>[];
    var faceCount = 0;
    _ObjectBuilder? current;

    _ObjectBuilder objectFor(String name) {
      if (current == null) {
        current = _ObjectBuilder(name);
        builders.add(current!);
      }
      return current!;
    }

    final lines = const LineSplitter().convert(content);
    for (var lineNumber = 0; lineNumber < lines.length; lineNumber++) {
      final trimmed = lines[lineNumber].trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('#')) {
        const key = '# blunder_texture_base64=';
        if (trimmed.startsWith(key)) {
          try {
            objectFor('Mesh_${builders.length + 1}').texturePath =
                utf8.decode(base64Url.decode(trimmed.substring(key.length)));
          } on FormatException catch (error) {
            throw FormatException(
              'Invalid texture metadata at line ${lineNumber + 1}: $error',
            );
          }
        } else if (trimmed.startsWith('# blunder_group_base64=')) {
          const groupKey = '# blunder_group_base64=';
          try {
            objectFor('Mesh_${builders.length + 1}').groupName = utf8
                .decode(base64Url.decode(trimmed.substring(groupKey.length)));
          } on FormatException catch (error) {
            throw FormatException(
              'Invalid group metadata at line ${lineNumber + 1}: $error',
            );
          }
        } else if (trimmed == '# blunder_smooth_shading=1') {
          objectFor('Mesh_${builders.length + 1}').smoothShading = true;
        } else if (trimmed.startsWith('# blunder_rv_metadata_base64=')) {
          const key = '# blunder_rv_metadata_base64=';
          try {
            final builder = objectFor('Mesh_${builders.length + 1}');
            final decoded = jsonDecode(
              utf8.decode(base64Url.decode(trimmed.substring(key.length))),
            );
            if (decoded is! Map<String, dynamic> ||
                decoded['scale'] is! num ||
                decoded['origin'] is! List ||
                (decoded['origin'] as List).length != 3) {
              throw const FormatException('Invalid RV scene metadata.');
            }
            final origin = decoded['origin'] as List;
            builder.rvCoordinateScale = (decoded['scale'] as num).toDouble();
            builder.rvCoordinateOrigin = Vec3(
              (origin[0] as num).toDouble(),
              (origin[1] as num).toDouble(),
              (origin[2] as num).toDouble(),
            );
            final animations = decoded['animations'];
            if (animations is List) {
              builder.rvTextureAnimations = [
                for (final animation in animations)
                  Uint8List.fromList(base64Url.decode(animation as String)),
              ];
            }
            final textures = decoded['textures'];
            if (textures is Map) {
              builder.rvTexturePaths = {
                for (final entry in textures.entries)
                  int.parse(entry.key as String): entry.value as String,
              };
            }
          } on FormatException catch (error) {
            throw FormatException(
              'Invalid RV metadata at line ${lineNumber + 1}: $error',
            );
          } on TypeError catch (error) {
            throw FormatException(
              'Invalid RV metadata at line ${lineNumber + 1}: $error',
            );
          }
        } else if (trimmed.startsWith('# blunder_rv_face_base64=')) {
          const key = '# blunder_rv_face_base64=';
          try {
            final builder = objectFor('Mesh_${builders.length + 1}');
            final decoded = jsonDecode(
              utf8.decode(base64Url.decode(trimmed.substring(key.length))),
            );
            if (decoded is! Map<String, dynamic>) {
              throw const FormatException('Invalid RV face metadata.');
            }
            builder.pendingRvFace = decoded;
          } on FormatException catch (error) {
            throw FormatException(
              'Invalid RV face metadata at line ${lineNumber + 1}: $error',
            );
          }
        }
        continue;
      }

      final parts = trimmed.split(RegExp(r'\s+'));
      final command = parts.first;
      final values = parts.skip(1).toList();
      try {
        switch (command) {
          case 'o':
          case 'g':
            final builder = _ObjectBuilder(
              values.isEmpty ? 'Mesh_${builders.length + 1}' : values.join(' '),
            );
            current = builder;
            builders.add(builder);
          case 'v':
            if (values.length < 3) {
              throw const FormatException('A vertex needs x, y, and z.');
            }
            final position = Vec3(
              double.parse(values[0]),
              double.parse(values[1]),
              double.parse(values[2]),
            );
            positions.add(position);
            final target = objectFor('Mesh_${builders.length + 1}');
            final globalIndex = positions.length - 1;
            target.localVertexByGlobal[globalIndex] =
                target.vertexIndices.length;
            target.vertexIndices.add(globalIndex);
          case 'vt':
            if (values.length < 2) {
              throw const FormatException('A UV coordinate needs u and v.');
            }
            textureCoordinates.add(
              Offset(double.parse(values[0]), double.parse(values[1])),
            );
          case 'f':
            final target = objectFor('Mesh_${builders.length + 1}');
            if (values.length != 3 && values.length != 4) {
              throw FormatException(
                'Only triangle and quad faces are supported, but this face has '
                '${values.length} corners.',
              );
            }
            if (faceCount >= maxFaceCount) {
              throw const FormatException(
                'Blunder supports up to 100000 faces per scene.',
              );
            }
            faceCount++;
            final faceVertices = <int>[];
            final faceUvs = <Offset>[];
            for (final value in values) {
              final indices = value.split('/');
              if (indices.isEmpty || indices.first.isEmpty) {
                throw const FormatException('A face vertex index is missing.');
              }
              final globalVertex =
                  _resolveIndex(indices.first, positions.length);
              final localVertex = target.localVertexByGlobal.putIfAbsent(
                globalVertex,
                () {
                  target.vertexIndices.add(globalVertex);
                  return target.vertexIndices.length - 1;
                },
              );
              faceVertices.add(localVertex);
              if (indices.length > 1 && indices[1].isNotEmpty) {
                final uvIndex =
                    _resolveIndex(indices[1], textureCoordinates.length);
                faceUvs.add(textureCoordinates[uvIndex]);
              }
            }
            final rvData = target.pendingRvFace;
            target.pendingRvFace = null;
            target.faces.add(
              MeshFace(
                faceVertices,
                faceUvs.length == values.length
                    ? faceUvs
                    : values.length == 3
                        ? const [
                            Offset(0.08, 0.08),
                            Offset(0.92, 0.08),
                            Offset(0.5, 0.92),
                          ]
                        : const [
                            Offset(0.08, 0.08),
                            Offset(0.92, 0.08),
                            Offset(0.92, 0.92),
                            Offset(0.08, 0.92),
                          ],
                rvType: rvData?['type'] is num
                    ? (rvData!['type'] as num).toInt()
                    : 0,
                rvTextureIndex: rvData?['texture'] is num
                    ? (rvData!['texture'] as num).toInt()
                    : 0,
                rvColors: rvData?['colors'] is List
                    ? (rvData!['colors'] as List)
                        .whereType<num>()
                        .map((color) => color.toInt())
                        .toList()
                    : const [],
                rvExtraColor: rvData?['extraColor'] is num
                    ? (rvData!['extraColor'] as num).toInt()
                    : null,
                rvExtraUv: rvData?['extraUv'] is List &&
                        (rvData!['extraUv'] as List).length == 2
                    ? Offset(
                        ((rvData['extraUv'] as List)[0] as num).toDouble(),
                        ((rvData['extraUv'] as List)[1] as num).toDouble(),
                      )
                    : null,
                rvEnvironmentColor: rvData?['environmentColor'] is num
                    ? (rvData!['environmentColor'] as num).toInt()
                    : null,
              ),
            );
          case 'mtllib':
          case 'usemtl':
          case 's':
            break;
          default:
            throw FormatException('Unsupported Wavefront command "$command".');
        }
      } on FormatException catch (error) {
        throw FormatException('Line ${lineNumber + 1}: ${error.message}');
      } on RangeError catch (error) {
        throw FormatException('Line ${lineNumber + 1}: Invalid index. $error');
      }
    }

    if (positions.isEmpty || builders.isEmpty) {
      throw const FormatException('This PKY file does not contain a mesh.');
    }

    return builders.map((builder) {
      final orderedVertices = builder.vertexIndices.toList();
      final localPositions =
          orderedVertices.map((index) => positions[index]).toList();
      final mesh = MeshModel.fromData(
        localPositions,
        builder.faces,
        smoothShading: builder.smoothShading,
      );
      return ModelMeshData(
        name: builder.name,
        mesh: mesh,
        texturePath: builder.texturePath,
        groupName: builder.groupName,
        rvCoordinateScale: builder.rvCoordinateScale,
        rvCoordinateOrigin: builder.rvCoordinateOrigin,
        rvTextureAnimations: builder.rvTextureAnimations,
        rvTexturePaths: builder.rvTexturePaths,
      );
    }).toList();
  }

  static List<ModelMeshData> decodeObj(
    String content, {
    required String baseDirectory,
    Map<String, String> materialLibraries = const {},
    String groupName = 'Imported OBJ',
  }) {
    final positions = <Vec3>[];
    final textureCoordinates = <Offset>[];
    final materials = <String, String>{};
    for (final entry in materialLibraries.entries) {
      final libraryDirectory = File(entry.key).isAbsolute
          ? File(entry.key).parent.path
          : baseDirectory;
      for (final material in _decodeMtl(entry.value).entries) {
        final normalized =
            material.value.replaceAll(RegExp(r'[\\/]'), Platform.pathSeparator);
        materials[material.key] = File(normalized).isAbsolute
            ? normalized
            : '$libraryDirectory${Platform.pathSeparator}$normalized';
      }
    }

    final builders = <_ObjectBuilder>[];
    var faceCount = 0;
    final buildersByKey = <String, _ObjectBuilder>{};
    var objectName = 'Mesh';
    var subgroupName = '';
    var materialName = '';
    var smoothShading = false;

    _ObjectBuilder builderForCurrentMaterial() {
      final key = '$objectName\u0000$subgroupName\u0000$materialName';
      final builder = buildersByKey.putIfAbsent(key, () {
        final name = [
          objectName,
          if (subgroupName.isNotEmpty) subgroupName,
          if (materialName.isNotEmpty) materialName,
        ].join('_');
        final texturePath = materials[materialName];
        final builder = _ObjectBuilder(name)
          ..groupName = groupName
          ..texturePath = texturePath;
        builders.add(builder);
        return builder;
      });
      builder.smoothShading = smoothShading;
      return builder;
    }

    final lines = const LineSplitter().convert(content);
    for (var lineNumber = 0; lineNumber < lines.length; lineNumber++) {
      final line = lines[lineNumber].split('#').first.trim();
      if (line.isEmpty) continue;
      final parts = line.split(RegExp(r'\s+'));
      final command = parts.first;
      final values = parts.skip(1).toList();
      try {
        switch (command) {
          case 'o':
            objectName =
                values.isEmpty ? 'Mesh' : _objectName(values.join(' '));
            subgroupName = '';
            materialName = '';
          case 'g':
            subgroupName = values.isEmpty ? '' : _objectName(values.join(' '));
          case 'v':
            if (values.length < 3) {
              throw const FormatException('A vertex needs x, y, and z.');
            }
            positions.add(
              Vec3(
                double.parse(values[0]),
                double.parse(values[1]),
                double.parse(values[2]),
              ),
            );
          case 'vt':
            if (values.length < 2) {
              throw const FormatException('A UV coordinate needs u and v.');
            }
            textureCoordinates.add(
              Offset(double.parse(values[0]), double.parse(values[1])),
            );
          case 'f':
            if (values.length < 3) {
              throw const FormatException(
                  'A face needs at least three corners.');
            }
            final target = builderForCurrentMaterial();
            final faceVertices = <int>[];
            final faceUvs = <Offset?>[];
            for (final value in values) {
              final indices = value.split('/');
              if (indices.first.isEmpty) {
                throw const FormatException('A face vertex index is missing.');
              }
              final globalVertex =
                  _resolveIndex(indices.first, positions.length);
              final localVertex = target.localVertexByGlobal.putIfAbsent(
                globalVertex,
                () {
                  target.vertexIndices.add(globalVertex);
                  return target.vertexIndices.length - 1;
                },
              );
              faceVertices.add(localVertex);
              if (indices.length > 1 && indices[1].isNotEmpty) {
                final uvIndex =
                    _resolveIndex(indices[1], textureCoordinates.length);
                faceUvs.add(textureCoordinates[uvIndex]);
              } else {
                faceUvs.add(null);
              }
            }
            final faceCorners = faceVertices.length <= 4
                ? [List.generate(faceVertices.length, (index) => index)]
                : [
                    for (var corner = 1;
                        corner < faceVertices.length - 1;
                        corner++)
                      [0, corner, corner + 1],
                  ];
            if (faceCount + faceCorners.length > maxFaceCount) {
              throw const FormatException(
                'Blunder supports up to 100000 faces per scene.',
              );
            }
            faceCount += faceCorners.length;
            for (final corners in faceCorners) {
              final uv = corners.map((index) => faceUvs[index]).toList();
              final fallbackUv = corners.length == 4
                  ? const [
                      Offset(0.08, 0.08),
                      Offset(0.92, 0.08),
                      Offset(0.92, 0.92),
                      Offset(0.08, 0.92),
                    ]
                  : const [
                      Offset(0.08, 0.08),
                      Offset(0.92, 0.08),
                      Offset(0.5, 0.92),
                    ];
              target.faces.add(
                MeshFace(
                  corners.map((index) => faceVertices[index]).toList(),
                  uv.every((coordinate) => coordinate != null)
                      ? uv.cast<Offset>()
                      : fallbackUv,
                ),
              );
            }
          case 'usemtl':
            materialName = values.join(' ');
          case 's':
            smoothShading = values.isNotEmpty &&
                values.first != 'off' &&
                values.first != '0';
            builderForCurrentMaterial().smoothShading = smoothShading;
          case 'mtllib':
          case 'vn':
          case 'vp':
          case 'l':
            break;
          default:
            break;
        }
      } on FormatException catch (error) {
        throw FormatException('Line ${lineNumber + 1}: ${error.message}');
      } on RangeError catch (error) {
        throw FormatException('Line ${lineNumber + 1}: Invalid index. $error');
      }
    }
    if (positions.isEmpty || builders.isEmpty) {
      throw const FormatException('This OBJ file does not contain any faces.');
    }

    return builders.map((builder) {
      final localPositions =
          builder.vertexIndices.map((index) => positions[index]).toList();
      return ModelMeshData(
        name: builder.name,
        mesh: MeshModel.fromData(
          localPositions,
          builder.faces,
          smoothShading: builder.smoothShading,
        ),
        texturePath: builder.texturePath,
        groupName: builder.groupName,
      );
    }).toList();
  }

  static Map<String, String> _decodeMtl(String content) {
    final textures = <String, String>{};
    String? currentMaterial;
    for (final rawLine in const LineSplitter().convert(content)) {
      final line = rawLine.split('#').first.trim();
      if (line.isEmpty) continue;
      final separator = line.indexOf(RegExp(r'\s'));
      final command = separator < 0 ? line : line.substring(0, separator);
      final value = separator < 0 ? '' : line.substring(separator).trim();
      if (command == 'newmtl') {
        currentMaterial = value;
      } else if (command == 'map_Kd' && currentMaterial != null) {
        textures[currentMaterial] = _mapTexturePath(value);
      }
    }
    return textures;
  }

  static String _mapTexturePath(String value) {
    final parts = value.split(RegExp(r'\s+'));
    var index = 0;
    const optionArguments = {
      '-blendu': 1,
      '-blendv': 1,
      '-boost': 1,
      '-bm': 1,
      '-clamp': 1,
      '-imfchan': 1,
      '-mm': 2,
      '-texres': 1,
      '-type': 1,
    };
    while (index < parts.length && parts[index].startsWith('-')) {
      final option = parts[index++];
      if (option == '-o' || option == '-s' || option == '-t') {
        var consumed = 0;
        while (index < parts.length &&
            consumed < 3 &&
            double.tryParse(parts[index]) != null) {
          index++;
          consumed++;
        }
      } else {
        index += optionArguments[option] ?? 0;
      }
    }
    final path = parts.skip(index).join(' ');
    return path.startsWith('"') && path.endsWith('"')
        ? path.substring(1, path.length - 1)
        : path;
  }

  static Future<List<ModelMeshData>> readObj(String path) async {
    final content = await File(path).readAsString();
    final libraries = <String, String>{};
    for (final rawLine in const LineSplitter().convert(content)) {
      final line = rawLine.split('#').first.trim();
      final separator = line.indexOf(RegExp(r'\s'));
      if (separator < 0 || line.substring(0, separator) != 'mtllib') continue;
      final names = line.substring(separator).trim();
      final candidates = names.startsWith('"') && names.endsWith('"')
          ? [names.substring(1, names.length - 1)]
          : names.split(RegExp(r'\s+'));
      for (final name in candidates) {
        final normalized =
            name.replaceAll(RegExp(r'[\\/]'), Platform.pathSeparator);
        final file = File(
          File(normalized).isAbsolute
              ? normalized
              : '${File(path).parent.path}${Platform.pathSeparator}$normalized',
        );
        if (await file.exists()) {
          libraries[file.path] = await file.readAsString();
        }
      }
    }
    final baseDirectory = File(path).parent.path;
    final groupName = File(path).uri.pathSegments.last.replaceFirst(
          RegExp(r'\.[^.]+$'),
          '',
        );
    final serialized = await Isolate.run(
      () => jsonEncode(
        decodeObj(
          content,
          baseDirectory: baseDirectory,
          materialLibraries: libraries,
          groupName: groupName,
        )
            .map(
              (object) => {
                'name': object.name,
                'texturePath': object.texturePath,
                'groupName': object.groupName,
                'vertices': [
                  for (final vertex in object.mesh.vertices)
                    [
                      vertex.position.x,
                      vertex.position.y,
                      vertex.position.z,
                    ],
                ],
                'faces': [
                  for (final face in object.mesh.faces)
                    {
                      'vertices': face.vertices,
                      'uv': [
                        for (final uv in face.uv) [uv.dx, uv.dy],
                      ],
                    },
                ],
              },
            )
            .toList(),
      ),
    );
    final decoded = jsonDecode(serialized) as List<dynamic>;
    return [
      for (final rawObject in decoded)
        _modelMeshFromJson(rawObject as Map<String, dynamic>),
    ];
  }

  static ModelMeshData _modelMeshFromJson(Map<String, dynamic> object) {
    final positions = (object['vertices'] as List<dynamic>).map((rawVertex) {
      final values = rawVertex as List<dynamic>;
      return Vec3(
        (values[0] as num).toDouble(),
        (values[1] as num).toDouble(),
        (values[2] as num).toDouble(),
      );
    });
    final faces = (object['faces'] as List<dynamic>).map((rawFace) {
      final face = rawFace as Map<String, dynamic>;
      final vertices = (face['vertices'] as List<dynamic>).cast<int>();
      final uv = (face['uv'] as List<dynamic>).map((rawUv) {
        final values = rawUv as List<dynamic>;
        return Offset(
          (values[0] as num).toDouble(),
          (values[1] as num).toDouble(),
        );
      });
      return MeshFace(vertices, uv.toList());
    });
    return ModelMeshData(
      name: object['name'] as String,
      mesh: MeshModel.fromData(positions, faces),
      texturePath: object['texturePath'] as String?,
      groupName: object['groupName'] as String?,
    );
  }

  static String encodeObj(Iterable<ModelMeshData> objects) {
    final objectList = objects.toList();
    _validateFaceCount(objectList);
    final output = StringBuffer('# Blunder OBJ export\n');
    var vertexOffset = 1;
    var uvOffset = 1;
    for (final object in objectList) {
      output.writeln('o ${_objectName(object.name)}');
      output.writeln(object.mesh.smoothShading ? 's 1' : 's off');
      for (final vertex in object.mesh.vertices) {
        final position = vertex.position;
        output.writeln('v ${_number(position.x)} '
            '${_number(position.y)} ${_number(position.z)}');
      }
      for (final face in object.mesh.faces) {
        for (final uv in face.uv) {
          output.writeln('vt ${_number(uv.dx)} ${_number(uv.dy)}');
        }
      }
      var faceUvOffset = uvOffset;
      for (final face in object.mesh.faces) {
        final refs = <String>[];
        for (var corner = 0; corner < face.vertices.length; corner++) {
          refs.add(
            '${face.vertices[corner] + vertexOffset}/'
            '${faceUvOffset + corner}',
          );
        }
        output.writeln('f ${refs.join(' ')}');
        faceUvOffset += face.uv.length;
      }
      vertexOffset += object.mesh.vertices.length;
      uvOffset += object.mesh.faces.fold<int>(
        0,
        (count, face) => count + face.uv.length,
      );
    }
    return output.toString();
  }

  static int _resolveIndex(String rawIndex, int length) {
    final index = int.parse(rawIndex);
    final resolved = index > 0 ? index - 1 : length + index;
    if (resolved < 0 || resolved >= length) {
      throw FormatException('Index $index is outside the available data.');
    }
    return resolved;
  }

  static String _number(double value) => value.toStringAsPrecision(9);

  static String _objectName(String name) =>
      name.trim().replaceAll(RegExp(r'\s+'), '_').isEmpty
          ? 'Mesh'
          : name.trim().replaceAll(RegExp(r'\s+'), '_');

  static Future<void> writePky(
    String path,
    Iterable<ModelMeshData> objects,
  ) async {
    final directory = File(path).parent.path;
    final basename = File(path).uri.pathSegments.last.split('.').first;
    final savedObjects = <ModelMeshData>[];
    var index = 0;
    for (final object in objects) {
      index++;
      final texturePath = object.texturePath;
      String? savedTexture;
      if (texturePath != null && await File(texturePath).exists()) {
        final extension = texturePath.split('.').last;
        savedTexture = '${basename}_mesh$index.$extension';
        await File(texturePath).copy(
          '$directory${Platform.pathSeparator}$savedTexture',
        );
      }
      final savedRvTexturePaths = <int, String>{};
      for (final entry in object.rvTexturePaths.entries) {
        final source = File(entry.value);
        if (!await source.exists()) {
          savedRvTexturePaths[entry.key] = entry.value;
          continue;
        }
        final extension = source.path.split('.').last;
        final savedName = '${basename}_mesh${index}_rv${entry.key}.$extension';
        await source.copy(
          '$directory${Platform.pathSeparator}$savedName',
        );
        savedRvTexturePaths[entry.key] = savedName;
      }
      savedObjects.add(
        ModelMeshData(
          name: object.name,
          mesh: object.mesh,
          texturePath: savedTexture,
          groupName: object.groupName,
          rvCoordinateScale: object.rvCoordinateScale,
          rvCoordinateOrigin: object.rvCoordinateOrigin,
          rvTextureAnimations: object.rvTextureAnimations,
          rvTexturePaths: savedRvTexturePaths,
        ),
      );
    }
    await File(path).writeAsString(encodePky(savedObjects));
  }

  static Future<List<ModelMeshData>> readPky(String path) async {
    final extension = path.split('.').last.toLowerCase();
    if (extension != 'pky' && extension != 'pkg') {
      throw const FormatException('Blunder opens .pky and .pkg files only.');
    }
    return decodePky(await File(path).readAsString());
  }

  static Future<void> writeObj(
    String path,
    Iterable<ModelMeshData> objects,
  ) async {
    final list = objects.toList();
    _validateFaceCount(list);
    final output = StringBuffer('# Blunder OBJ export\n');
    final materialName =
        path.replaceAll(RegExp(r'\.obj$', caseSensitive: false), '.mtl');
    final materialFile = File(materialName);
    final hasTexture = list.any(
      (object) =>
          object.texturePath != null && File(object.texturePath!).existsSync(),
    );
    if (hasTexture) {
      output.writeln('mtllib ${materialFile.uri.pathSegments.last}');
    }

    var vertexOffset = 1;
    var uvOffset = 1;
    final material = StringBuffer('# Blunder material library\n');
    for (var objectIndex = 0; objectIndex < list.length; objectIndex++) {
      final object = list[objectIndex];
      output.writeln('o ${_objectName(object.name)}');
      output.writeln(object.mesh.smoothShading ? 's 1' : 's off');
      for (final vertex in object.mesh.vertices) {
        final position = vertex.position;
        output.writeln('v ${_number(position.x)} '
            '${_number(position.y)} ${_number(position.z)}');
      }
      for (final face in object.mesh.faces) {
        for (final uv in face.uv) {
          output.writeln('vt ${_number(uv.dx)} ${_number(uv.dy)}');
        }
      }

      final sourceTexture = object.texturePath;
      String? textureFilename;
      if (sourceTexture != null && await File(sourceTexture).exists()) {
        final extension = sourceTexture.split('.').last;
        textureFilename =
            '${materialFile.uri.pathSegments.last.split('.').first}'
            '_mesh${objectIndex + 1}.$extension';
        final directory = File(path).parent.path;
        await File(sourceTexture).copy(
          '$directory${Platform.pathSeparator}$textureFilename',
        );
      }
      if (textureFilename != null) {
        final name = 'blunder_material_${objectIndex + 1}';
        output.writeln('usemtl $name');
        material
          ..writeln('newmtl $name')
          ..writeln('Ka 1.000000 1.000000 1.000000')
          ..writeln('Kd 1.000000 1.000000 1.000000')
          ..writeln('d 1.000000')
          ..writeln('illum 1')
          ..writeln('map_Kd $textureFilename')
          ..writeln();
      }
      var faceUvOffset = uvOffset;
      for (final face in object.mesh.faces) {
        final refs = <String>[];
        for (var corner = 0; corner < face.vertices.length; corner++) {
          refs.add(
            '${face.vertices[corner] + vertexOffset}/'
            '${faceUvOffset + corner}',
          );
        }
        output.writeln('f ${refs.join(' ')}');
        faceUvOffset += face.uv.length;
      }
      vertexOffset += object.mesh.vertices.length;
      uvOffset += object.mesh.faces.fold<int>(
        0,
        (count, face) => count + face.uv.length,
      );
    }
    await File(path).writeAsString(output.toString());
    if (hasTexture) await materialFile.writeAsString(material.toString());
  }
}

class _ObjectBuilder {
  _ObjectBuilder(this.name);

  final String name;
  final List<int> vertexIndices = [];
  final Map<int, int> localVertexByGlobal = {};
  final List<MeshFace> faces = [];
  String? texturePath;
  String? groupName;
  bool smoothShading = false;
  double? rvCoordinateScale;
  Vec3? rvCoordinateOrigin;
  List<Uint8List> rvTextureAnimations = [];
  Map<int, String> rvTexturePaths = {};
  Map<String, dynamic>? pendingRvFace;
}
