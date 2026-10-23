import 'dart:io';

import 'package:blunder/mesh.dart';
import 'package:blunder/model_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ModelIo', () {
    test('round-trips multiple meshes, quad UVs, and texture metadata', () {
      final first = MeshModel.starterPlane();
      first.updateUv(0, 2, const Offset(0.7, 0.6));
      final second = MeshModel.starterPlane()
        ..moveVertices(
          [0, 1, 2, 3],
          const Vec3(3, 0, 2),
        );
      final encoded = ModelIo.encodePky([
        ModelMeshData(
          name: 'Main Mesh',
          mesh: first,
          texturePath: r'D:\Textures\stone.png',
          groupName: 'Imported',
        ),
        ModelMeshData(name: 'SideMesh', mesh: second),
      ]);

      final decoded = ModelIo.decodePky(encoded);

      expect(decoded, hasLength(2));
      expect(decoded[0].name, 'Main Mesh');
      expect(decoded[0].texturePath, r'D:\Textures\stone.png');
      expect(decoded[0].groupName, 'Imported');
      expect(decoded[0].mesh.vertices, hasLength(4));
      expect(decoded[0].mesh.faces.single.vertices, [0, 1, 2, 3]);
      expect(decoded[0].mesh.faces.single.uv[2], const Offset(0.7, 0.6));
      expect(decoded[1].mesh.vertices[0].position.x, 2);
      expect(decoded[1].mesh.vertices[0].position.z, 2);
    });

    test('rejects non-quad or invalid face indices with a line number', () {
      expect(
        () => ModelIo.decodePky(
          'o Mesh_1\nv 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\n'
          'v 2 1 0\nf 1 2 3 4 5\n',
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Line 7'),
          ),
        ),
      );
      expect(
        () => ModelIo.decodePky(
          'o Mesh_1\nv 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\nf 1 2 3 9\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('round-trips triangular face geometry and UVs', () {
      final mesh = MeshModel.empty()
        ..addVertex(const Vec3(0, 0, 0))
        ..addVertex(const Vec3(1, 0, 0))
        ..addVertex(const Vec3(0, 1, 0))
        ..addTriangle([0, 1, 2]);
      final decoded = ModelIo.decodePky(ModelIo.encodePky([
        ModelMeshData(name: 'Triangle', mesh: mesh),
      ]));

      expect(decoded.single.mesh.faces.single.vertices, [0, 1, 2]);
      expect(decoded.single.mesh.faces.single.uv, hasLength(3));
    });

    test('writes a PKY project that can be reopened from disk', () async {
      final directory = await Directory.systemTemp.createTemp('blunder_pky_');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}\\test_scene.pky';

      await ModelIo.writePky(
        path,
        [ModelMeshData(name: 'Mesh_1', mesh: MeshModel.starterPlane())],
      );
      final loaded = await ModelIo.readPky(path);

      expect(loaded, hasLength(1));
      expect(loaded.single.mesh.faces, hasLength(1));
      expect(loaded.single.mesh.vertices, hasLength(4));

      final pkgPath = '${directory.path}\\alternate.pkg';
      await File(pkgPath).writeAsString(
        ModelIo.encodePky([
          ModelMeshData(name: 'Mesh_1', mesh: MeshModel.starterPlane()),
        ]),
      );
      expect(await ModelIo.readPky(pkgPath), hasLength(1));
    });

    test('exports OBJ-compatible geometry and UV face indices', () {
      final obj = ModelIo.encodeObj([
        ModelMeshData(name: 'Mesh 1', mesh: MeshModel.starterPlane()),
      ]);

      expect(obj, contains('o Mesh_1'));
      expect(obj, contains('vt 0.0800000000 0.0800000000'));
      expect(obj, contains('f 1/1 2/2 3/3 4/4'));
    });

    test('imports OBJ submeshes, material textures, and polygon faces',
        () async {
      final directory = await Directory.systemTemp.createTemp('blunder_obj_');
      addTearDown(() => directory.delete(recursive: true));
      final mtlPath = '${directory.path}${Platform.pathSeparator}model.mtl';
      final objPath = '${directory.path}${Platform.pathSeparator}model.obj';
      await File(mtlPath).writeAsString(
        'newmtl stone\nmap_Kd -s 1 1 1 tile texture.png\n'
        'newmtl plain\nKd 0.8 0.8 0.8\n',
      );
      await File(objPath).writeAsString(
        'mtllib model.mtl\n'
        'o Building\n'
        'v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\nv 0.5 2 0\n'
        'vt 0 0\nvt 1 0\nvt 1 1\nvt 0 1\nvt 0.5 1\n'
        'g shell\n'
        'usemtl stone\nf 1/1 2/2 3/3 4/4\n'
        'g base\n'
        'usemtl plain\nf -5/1 -2/4 -1/5\n',
      );

      final imported = await ModelIo.readObj(objPath);

      expect(imported, hasLength(2));
      expect(imported[0].name, 'Building_shell_stone');
      expect(imported[0].groupName, 'model');
      expect(imported[0].texturePath,
          '${directory.path}${Platform.pathSeparator}tile texture.png');
      expect(imported[0].mesh.faces.single.vertices, [0, 1, 2, 3]);
      expect(imported[0].mesh.faces.single.uv[2], const Offset(1, 1));
      expect(imported[1].name, 'Building_base_plain');
      expect(imported[1].mesh.faces.single.vertices, [0, 1, 2]);
      expect(imported[1].mesh.faces.single.uv, hasLength(3));
    });

    test('triangulates imported OBJ polygons and handles negative indices', () {
      final imported = ModelIo.decodeObj(
        'o Surface\n'
        'v 0 0 0\nv 1 0 0\nv 2 1 0\nv 1 2 0\nv 0 1 0\n'
        'f -5 -4 -3 -2 -1\n',
        baseDirectory: Directory.systemTemp.path,
      );

      expect(imported.single.mesh.vertices, hasLength(5));
      expect(imported.single.mesh.faces, hasLength(3));
      expect(
        imported.single.mesh.faces.every((face) => face.vertices.length == 3),
        isTrue,
      );
    });
  });
}
