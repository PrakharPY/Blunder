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

    test('connects vertices into quads on vertical planes', () {
      for (final positions in [
        const [
          Vec3(-1, 0, -1),
          Vec3(1, 0, -1),
          Vec3(1, 0, 1),
          Vec3(-1, 0, 1),
        ],
        const [
          Vec3(0, -1, -1),
          Vec3(0, 1, -1),
          Vec3(0, 1, 1),
          Vec3(0, -1, 1),
        ],
      ]) {
        final mesh = MeshModel.empty();
        for (final position in positions) {
          mesh.addVertex(position);
        }

        expect(mesh.addQuad([2, 0, 3, 1]), isTrue);
        expect(mesh.faces.single.vertices.toSet(), {0, 1, 2, 3});
      }
    });

    test('duplicates and moves a face without changing the original', () {
      final mesh = MeshModel.starterPlane();
      final duplicate = mesh.duplicateFace(0);

      expect(duplicate, 1);
      expect(mesh.vertices, hasLength(8));
      expect(mesh.faces, hasLength(2));
      expect(mesh.moveVertices(mesh.faces[1].vertices, const Vec3(0, 0, 2)),
          isTrue);
      expect(mesh.vertices[0].position.z, 0);
      expect(mesh.vertices[4].position.z, 2);
      expect(mesh.faces[1].uv, mesh.faces[0].uv);
    });

    test('duplicates selected vertices and moves them along one axis', () {
      final mesh = MeshModel.starterPlane();
      final duplicated = mesh.duplicateVertices([0, 2]);

      expect(duplicated, [4, 5]);
      expect(mesh.moveVertices(duplicated, const Vec3(0, 3, 0)), isTrue);
      expect(mesh.vertices[4].position.y, 2);
      expect(mesh.vertices[5].position.y, 4);
      expect(mesh.vertices[0].position.y, -1);
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
