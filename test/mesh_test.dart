import 'dart:ui';

import 'package:blunder/mesh.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MeshModel', () {
    test('starts with one flat quad and a matching UV layout', () {
      final mesh = MeshModel.starterPlane();

      expect(mesh.vertices, hasLength(4));
      expect(mesh.faces, hasLength(1));
      expect(mesh.faces.single.vertices, [0, 1, 2, 3]);
      expect(mesh.faces.single.uv, hasLength(4));
    });

    test('connects four selected vertices into a quad', () {
      final mesh = MeshModel.empty()
        ..addVertex(const Vec3(-1, -1, 0))
        ..addVertex(const Vec3(1, -1, 0))
        ..addVertex(const Vec3(1, 1, 0))
        ..addVertex(const Vec3(-1, 1, 0));

      expect(mesh.addQuad([2, 0, 3, 1]), isTrue);
      expect(mesh.faces, hasLength(1));
      expect(mesh.faces.single.vertices.toSet(), {0, 1, 2, 3});
      expect(mesh.addQuad([0, 1, 2, 3]), isFalse);
    });

    test('rejects invalid, duplicate, and degenerate selections', () {
      final mesh = MeshModel.empty()
        ..addVertex(const Vec3(0, 0, 0))
        ..addVertex(const Vec3(1, 0, 0))
        ..addVertex(const Vec3(2, 0, 0))
        ..addVertex(const Vec3(3, 0, 0));

      expect(mesh.addQuad([0, 1, 2]), isFalse);
      expect(mesh.addQuad([0, 1, 2, 8]), isFalse);
      expect(mesh.addQuad([0, 1, 2, 3]), isFalse);
      expect(mesh.faces, isEmpty);
    });

    test('updates UV corners and clamps them to the UV tile', () {
      final mesh = MeshModel.starterPlane();

      expect(mesh.updateUv(0, 1, const Offset(1.5, -0.2)), isTrue);
      expect(mesh.faces.single.uv[1], const Offset(1, 0));
      expect(mesh.updateUv(3, 0, Offset.zero), isFalse);
    });
  });
}
