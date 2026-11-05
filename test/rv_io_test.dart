import 'dart:io';
import 'dart:typed_data';

import 'package:blunder/mesh.dart';
import 'package:blunder/rv_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RvModelIo', () {
    final quad = MeshModel.fromData(
      const [
        Vec3(-1, -1, 0),
        Vec3(1, -1, 0),
        Vec3(1, 1, 0),
        Vec3(-1, 1, 0),
      ],
      [
        MeshFace(
          const [0, 1, 2, 3],
          const [
            Offset(0.1, 0.2),
            Offset(0.9, 0.2),
            Offset(0.9, 0.8),
            Offset(0.1, 0.8),
          ],
          rvType: rvFlagInvisible | rvFlagEnvMap | rvFlagDoubleSided,
          rvTextureIndex: 2,
          rvColors: const [0xff112233, 0xff223344, 0xff334455, 0xff445566],
          rvEnvironmentColor: 0xffabcdef,
        ),
      ],
    );

    test('round-trips PRM quad metadata and coordinates', () {
      final encoded = RvModelIo.encodePrm([
        RvExportMesh(mesh: quad),
      ]);
      final imported = RvModelIo.decodePrm(encoded, name: 'test');
      final result = imported.meshes.single;
      final face = result.mesh.faces.single;

      expect(imported.isWorld, isFalse);
      expect(imported.lodCount, 1);
      expect(result.name, 'test');
      expect(result.mesh.vertices, hasLength(4));
      expect(face.vertices, hasLength(4));
      expect(face.rvType & rvFlagInvisible, isNot(0));
      expect(face.rvType & rvFlagEnvMap, isNot(0));
      expect(face.rvTextureIndex, 2);
      expect(face.rvColors, hasLength(4));
      expect(face.uv.first.dx, closeTo(0.1, 1e-5));
      expect(face.uv.first.dy, closeTo(0.2, 1e-5));
    });

    test('round-trips W mesh flags, texture IDs, and environment colors', () {
      final encoded = RvModelIo.encodeWorld([
        RvExportMesh(mesh: quad),
      ]);
      final imported = RvModelIo.decodeWorld(encoded, name: 'world');
      final face = imported.meshes.single.mesh.faces.single;

      expect(imported.isWorld, isTrue);
      expect(imported.meshes, hasLength(1));
      expect(face.rvType & rvFlagInvisible, isNot(0));
      expect(face.rvType & rvFlagDoubleSided, isNot(0));
      expect(face.rvTextureIndex, 2);
      expect(face.rvEnvironmentColor, 0xffabcdef);
      expect(imported.environmentColors, hasLength(4));
    });

    test('reads PRM and W files through the background isolate', () async {
      final directory = await Directory.systemTemp.createTemp('blunder_rv_');
      addTearDown(() => directory.delete(recursive: true));
      final prmPath = '${directory.path}${Platform.pathSeparator}model.prm';
      final worldPath = '${directory.path}${Platform.pathSeparator}world.w';
      await File(prmPath).writeAsBytes(
        RvModelIo.encodePrm([RvExportMesh(mesh: quad)]),
      );
      await File(worldPath).writeAsBytes(
        RvModelIo.encodeWorld([RvExportMesh(mesh: quad)]),
      );

      final prm = await RvModelIo.readPrm(prmPath);
      final world = await RvModelIo.readWorld(worldPath);

      expect(prm.meshes.single.mesh.faces, hasLength(1));
      expect(world.meshes.single.mesh.faces, hasLength(1));
    });

    test('rejects truncated headers and invalid geometry indices', () {
      expect(
        () => RvModelIo.decodePrm(Uint8List.fromList([0, 0, 4])),
        throwsA(isA<FormatException>()),
      );
      final invalid = Uint8List(4 + 60 + 24);
      final header = ByteData.sublistView(invalid);
      header
        ..setUint16(0, 1, Endian.little)
        ..setUint16(2, 1, Endian.little)
        ..setUint16(4, rvFlagQuad, Endian.little)
        ..setUint16(8, 1, Endian.little);
      expect(
        () => RvModelIo.decodePrm(invalid),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
