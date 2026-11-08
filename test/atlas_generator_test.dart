import 'package:blunder/atlas_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AtlasTextureRegistry', () {
    test('reuses a packed region for repeated source texture keys', () {
      final registry = AtlasTextureRegistry<String>();

      expect(
          registry.indexFor(r'path:C:\textures\blue.png', 'first decode'), 0);
      expect(
          registry.indexFor(r'path:C:\textures\blue.png', 'second decode'), 0);
      expect(registry.indexFor(r'path:C:\textures\red.png', 'red'), 1);
      expect(registry.textures, ['first decode', 'red']);
    });
  });

  group('AtlasPacker', () {
    test('packs multiple textures into an auto-fit square', () {
      final layout = AtlasPacker.pack(
        textures: const [
          AtlasTextureSize(256, 256),
          AtlasTextureSize(256, 256),
          AtlasTextureSize(128, 256),
        ],
        maxSize: 2048,
        padding: 8,
        shape: AtlasShape.square,
      );

      expect(layout.width, layout.height);
      expect(layout.width, lessThan(2048));
      expect(layout.regions, hasLength(3));
      for (final region in layout.regions) {
        expect(region.x, greaterThanOrEqualTo(8));
        expect(region.y, greaterThanOrEqualTo(8));
        expect(region.x + region.width, lessThanOrEqualTo(layout.width - 8));
        expect(region.y + region.height, lessThanOrEqualTo(layout.height - 8));
      }
      for (var first = 0; first < layout.regions.length; first++) {
        for (var second = first + 1; second < layout.regions.length; second++) {
          expect(_overlaps(layout.regions[first], layout.regions[second]),
              isFalse);
        }
      }
    });

    test('supports fixed landscape and portrait shapes and density', () {
      final landscape = AtlasPacker.pack(
        textures: const [AtlasTextureSize(128, 256)],
        maxSize: 1024,
        padding: 4,
        shape: AtlasShape.landscape,
        autoFit: false,
      );
      final portrait = AtlasPacker.pack(
        textures: const [AtlasTextureSize(128, 256)],
        maxSize: 1024,
        padding: 4,
        shape: AtlasShape.portrait,
        density: 0.5,
        autoFit: false,
      );

      expect(landscape.width, 1024);
      expect(landscape.height, 512);
      expect(portrait.width, 512);
      expect(portrait.height, 1024);
      expect(portrait.regions.single.width, 64);
      expect(portrait.regions.single.height, 128);
    });

    test('remaps UVs into a texture region with the renderer V convention', () {
      final uv = AtlasPacker.remapUv(
        uv: const Offset(0.25, 0.75),
        source: const AtlasTextureSize(100, 100),
        region: const AtlasRegion(x: 200, y: 100, width: 100, height: 100),
        atlas: const AtlasLayout(
          width: 500,
          height: 400,
          regions: [],
        ),
      );

      expect(uv.dx, closeTo(0.45, 1e-6));
      expect(uv.dy, closeTo(0.6875, 1e-6));
    });

    test('fails clearly when a texture cannot fit the maximum size', () {
      expect(
        () => AtlasPacker.pack(
          textures: const [AtlasTextureSize(4096, 256)],
          maxSize: 512,
          padding: 8,
          shape: AtlasShape.square,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

bool _overlaps(AtlasRegion first, AtlasRegion second) =>
    first.x < second.x + second.width &&
    first.x + first.width > second.x &&
    first.y < second.y + second.height &&
    first.y + first.height > second.y;
