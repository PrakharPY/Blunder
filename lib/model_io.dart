import 'dart:convert';
import 'dart:io';

import 'dart:ui' show Offset;

import 'mesh.dart';

class ModelMeshData {
  const ModelMeshData({
    required this.name,
    required this.mesh,
    this.texturePath,
    this.groupName,
  });

  final String name;
  final MeshModel mesh;
  final String? texturePath;
  final String? groupName;
}

class ModelIo {
  static String encodePky(Iterable<ModelMeshData> objects) {
    final output = StringBuffer(
      '# Blunder PKY 1.0 (Wavefront OBJ-compatible geometry)\n',
    );
    var vertexOffset = 1;
    var uvOffset = 1;
    for (final object in objects) {
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

  static List<ModelMeshData> decodePky(String content) {
    final positions = <Vec3>[];
    final textureCoordinates = <Offset>[];
    final builders = <_ObjectBuilder>[];
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
      final mesh = MeshModel.fromData(localPositions, builder.faces);
      return ModelMeshData(
        name: builder.name,
        mesh: mesh,
        texturePath: builder.texturePath,
        groupName: builder.groupName,
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
    final buildersByKey = <String, _ObjectBuilder>{};
    var objectName = 'Mesh';
    var subgroupName = '';
    var materialName = '';

    _ObjectBuilder builderForCurrentMaterial() {
      final key = '$objectName\u0000$subgroupName\u0000$materialName';
      return buildersByKey.putIfAbsent(key, () {
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
          case 'mtllib':
          case 'vn':
          case 's':
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
        mesh: MeshModel.fromData(localPositions, builder.faces),
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
    return decodeObj(
      content,
      baseDirectory: File(path).parent.path,
      materialLibraries: libraries,
      groupName: File(path).uri.pathSegments.last.replaceFirst(
            RegExp(r'\.[^.]+$'),
            '',
          ),
    );
  }

  static String encodeObj(Iterable<ModelMeshData> objects) {
    final output = StringBuffer('# Blunder OBJ export\n');
    var vertexOffset = 1;
    var uvOffset = 1;
    for (final object in objects) {
      output.writeln('o ${_objectName(object.name)}');
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
      savedObjects.add(
        ModelMeshData(
          name: object.name,
          mesh: object.mesh,
          texturePath: savedTexture,
          groupName: object.groupName,
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
}
