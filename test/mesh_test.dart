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

    test('creates a flat grid surface with continuous UV coordinates', () {
      final mesh = MeshModel.empty();

      expect(
        mesh.addGridSurface(
          const [
            Vec3(-2, 2, 0),
            Vec3(2, 2, 0),
            Vec3(2, -2, 0),
            Vec3(-2, -2, 0),
          ],
          3,
          2,
        ),
        isTrue,
      );
      expect(mesh.vertices, hasLength(12));
      expect(mesh.faces, hasLength(6));
      expect(mesh.faces.every((face) => face.vertices.length == 4), isTrue);
      expect(
        mesh.faces.expand((face) => face.uv).toSet(),
        containsAll([
          const Offset(0, 1),
          const Offset(1 / 3, 0.5),
          const Offset(1, 0),
        ]),
      );
      expect(
        mesh.addGridSurface(
          const [
            Vec3(0, 0, 0),
            Vec3(1, 0, 0),
            Vec3(1, 1, 0),
            Vec3(0, 1, 0),
          ],
          0,
          2,
        ),
        isFalse,
      );
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

    test('creates a triangle strip and merges adjacent triangles into a quad',
        () {
      final mesh = MeshModel.empty()
        ..addVertex(const Vec3(0, 0, 0))
        ..addVertex(const Vec3(1, 0, 0))
        ..addVertex(const Vec3(1, 1, 0))
        ..addVertex(const Vec3(0, 1, 0));

      expect(mesh.addTriangle([0, 1, 2]), isTrue);
      expect(mesh.addTriangle([0, 2, 3]), isTrue);
      expect(mesh.faces, hasLength(2));
      expect(mesh.faces.every((face) => face.vertices.length == 3), isTrue);

      final merged = mesh.mergeTriangles([0, 1]);

      expect(merged, 0);
      expect(mesh.faces, hasLength(1));
      expect(mesh.faces.single.vertices, hasLength(4));
      expect(mesh.faces.single.vertices.toSet(), {0, 1, 2, 3});
      expect(mesh.faces.single.uv, hasLength(4));
    });

    test('joins two vertices and removes collapsed faces', () {
      final mesh = MeshModel.fromData(
        const [
          Vec3(0, 0, 0),
          Vec3(1, 0, 0),
          Vec3(1, 1, 0),
          Vec3(0, 1, 0),
          Vec3(-1, 0, 0),
        ],
        [
          MeshFace(
            [0, 1, 2, 3],
            const [
              Offset(0, 0),
              Offset(1, 0),
              Offset(1, 1),
              Offset(0, 1),
            ],
          ),
          MeshFace(
            [0, 4, 1],
            const [Offset.zero, Offset(0.5, 0.5), Offset(1, 0)],
          ),
        ],
      );

      expect(mesh.joinVertices([0, 1]), isTrue);
      expect(mesh.vertices, hasLength(4));
      expect(mesh.vertices.first.position.x, closeTo(0.5, 1e-9));
      expect(mesh.faces, hasLength(1));
      expect(mesh.faces.single.vertices, [0, 1, 2]);
      expect(mesh.faces.single.uv,
          [const Offset(0, 0), const Offset(1, 1), const Offset(0, 1)]);
      expect(mesh.joinVertices([0, 0]), isFalse);
    });

    test('flips selected face winding without changing its UV mapping', () {
      final mesh = MeshModel.starterPlane();
      final originalUvs = mesh.faces.single.uv.toList();

      expect(mesh.flipFaceNormals([0]), isTrue);
      expect(mesh.faces.single.vertices, [3, 2, 1, 0]);
      expect(mesh.faces.single.uv, originalUvs.reversed);
      expect(mesh.flipFaceNormals([1]), isFalse);
    });

    test('joins mesh geometry while preserving face UVs', () {
      final first = MeshModel.starterPlane();
      final second = MeshModel.starterPlane()
        ..moveVertices([0, 1, 2, 3], const Vec3(3, 0, 0));

      final joined = MeshModel.join([first, second]);

      expect(joined.vertices, hasLength(8));
      expect(joined.faces, hasLength(2));
      expect(joined.faces[1].vertices, [4, 5, 6, 7]);
      expect(joined.faces[1].uv, second.faces.single.uv);
      expect(joined.vertices[4].position.x, 2);
    });

    test('rotates a selection around its center and mirrors mesh winding', () {
      final mesh = MeshModel.starterPlane();

      expect(mesh.rotateVertices([0, 1], 2, 90), isTrue);
      expect(mesh.vertices[0].position.x, closeTo(0, 1e-9));
      expect(mesh.vertices[0].position.y, closeTo(-2, 1e-9));
      expect(mesh.vertices[1].position.x, closeTo(0, 1e-9));
      expect(mesh.vertices[1].position.y, closeTo(0, 1e-9));

      final originalFace = mesh.faces.single.vertices.toList();
      expect(mesh.mirror(0), isTrue);
      expect(mesh.vertices[0].position.x, closeTo(0, 1e-9));
      expect(mesh.faces.single.vertices, originalFace.reversed);
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

    test('uniformly scales around the mesh centroid', () {
      final mesh = MeshModel.starterPlane();

      expect(mesh.scaleUniform(1.25), isTrue);
      expect(mesh.vertices[0].position.x, closeTo(-1.25, 1e-9));
      expect(mesh.vertices[0].position.y, closeTo(-1.25, 1e-9));
      expect(mesh.vertices[2].position.x, closeTo(1.25, 1e-9));
      expect(mesh.vertices[2].position.y, closeTo(1.25, 1e-9));
      expect(mesh.scaleUniform(0), isFalse);
      expect(mesh.scaleUniform(double.nan), isFalse);
    });

    test('deletes selected vertices and incident faces with remapped indices',
        () {
      final mesh = MeshModel.fromData(
        const [
          Vec3(0, 0, 0),
          Vec3(1, 0, 0),
          Vec3(1, 1, 0),
          Vec3(0, 1, 0),
          Vec3(2, 0, 0),
        ],
        [
          MeshFace(
            [0, 1, 2, 3],
            const [
              Offset(0, 0),
              Offset(1, 0),
              Offset(1, 1),
              Offset(0, 1),
            ],
          ),
          MeshFace(
            [1, 4, 2],
            const [Offset.zero, Offset(1, 0), Offset(1, 1)],
          ),
        ],
      );

      expect(mesh.deleteVertices([0]), isTrue);
      expect(mesh.vertices, hasLength(4));
      expect(mesh.faces, hasLength(1));
      expect(mesh.faces.single.vertices, [0, 3, 1]);
      expect(mesh.deleteVertices([8]), isFalse);
    });

    test('deletes multiple faces while keeping remaining face topology', () {
      final mesh = MeshModel.starterPlane();
      mesh.duplicateFace(0);

      expect(mesh.deleteFaces([0]), isTrue);
      expect(mesh.faces, hasLength(1));
      expect(mesh.faces.single.vertices, [4, 5, 6, 7]);
      expect(mesh.deleteFaces([4]), isFalse);
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

    test('smart UV remap separates face islands and fits them in the tile', () {
      final mesh = MeshModel.starterPlane();
      mesh.duplicateFace(0);
      mesh.moveVertices([4, 5, 6, 7], const Vec3(3, 0, 0));

      expect(mesh.smartUvRemap(), isTrue);
      final firstUvs = mesh.faces[0].uv;
      final secondUvs = mesh.faces[1].uv;
      expect(firstUvs.every((uv) => uv.dx >= 0 && uv.dx < 0.5), isTrue);
      expect(secondUvs.every((uv) => uv.dx > 0.5 && uv.dx <= 1), isTrue);
      expect(
        mesh.faces.expand((face) => face.uv).every(
            (uv) => uv.dx >= 0 && uv.dx <= 1 && uv.dy >= 0 && uv.dy <= 1),
        isTrue,
      );
      expect(MeshModel.empty().smartUvRemap(), isFalse);
    });
  });
}
