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
        padding: 0,
      );

      expect(layout.width, layout.height);
      expect(layout.width, lessThan(2048));
      expect(layout.regions, hasLength(3));
      for (final region in layout.regions) {
        expect(region.x, greaterThanOrEqualTo(0));
        expect(region.y, greaterThanOrEqualTo(0));
        expect(region.x + region.width, lessThanOrEqualTo(layout.width));
        expect(region.y + region.height, lessThanOrEqualTo(layout.height));
      }
      for (var first = 0; first < layout.regions.length; first++) {
        for (var second = first + 1; second < layout.regions.length; second++) {
          expect(_overlaps(layout.regions[first], layout.regions[second]),
              isFalse);
        }
      }
    });

    test('fits four unchanged 512px textures in a 1024px square', () {
      final layout = AtlasPacker.pack(
        textures: const [
          AtlasTextureSize(512, 512),
          AtlasTextureSize(512, 512),
          AtlasTextureSize(512, 512),
          AtlasTextureSize(512, 512),
        ],
        maxSize: 4096,
        padding: 0,
      );

      expect((layout.width, layout.height), (1024, 1024));
      expect(
        layout.regions.map((region) => (region.width, region.height)),
        everyElement((512, 512)),
      );
      expect(_regionsDoNotOverlap(layout.regions), isTrue);
    });

    test('packs three 2048px and two 1024px textures in a 4096 square', () {
      final layout = AtlasPacker.pack(
        textures: const [
          AtlasTextureSize(2048, 2048),
          AtlasTextureSize(2048, 2048),
          AtlasTextureSize(2048, 2048),
          AtlasTextureSize(1024, 1024),
          AtlasTextureSize(1024, 1024),
        ],
        maxSize: 4096,
        padding: 0,
      );

      expect((layout.width, layout.height), (4096, 4096));
      expect(
        layout.regions.map((region) => (region.width, region.height)),
        [
          (2048, 2048),
          (2048, 2048),
          (2048, 2048),
          (1024, 1024),
          (1024, 1024),
        ],
      );
      expect(_regionsDoNotOverlap(layout.regions), isTrue);
    });

    test('resizes source textures proportionally to fit a fixed atlas size',
        () {
      final layout = AtlasPacker.pack(
        textures: const [
          AtlasTextureSize(2048, 2048),
          AtlasTextureSize(2048, 2048),
          AtlasTextureSize(2048, 2048),
          AtlasTextureSize(1024, 1024),
          AtlasTextureSize(1024, 1024),
        ],
        maxSize: 1024,
        padding: 0,
      );

      expect((layout.width, layout.height), (1024, 1024));
      expect(layout.requiresResize, isTrue);
      expect(
        layout.regions.map((region) => (region.width, region.height)),
        [
          (512, 512),
          (512, 512),
          (512, 512),
          (256, 256),
          (256, 256),
        ],
      );
      expect(_regionsDoNotOverlap(layout.regions), isTrue);
    });

    test('keeps source textures unchanged when they fit the selected size', () {
      final layout = AtlasPacker.pack(
        textures: const [
          AtlasTextureSize(512, 512),
          AtlasTextureSize(512, 512),
        ],
        maxSize: 1024,
        padding: 0,
        autoFit: false,
      );

      expect(layout.requiresResize, isFalse);
      expect(
        layout.regions.map((region) => (region.width, region.height)),
        everyElement((512, 512)),
      );
    });

    test('padding reserves gutters without resizing source textures', () {
      final layout = AtlasPacker.pack(
        textures: const [AtlasTextureSize(128, 256)],
        maxSize: 1024,
        padding: 8,
      );

      expect((layout.width, layout.height), (512, 512));
      expect(layout.regions.single.width, 128);
      expect(layout.regions.single.height, 256);
      expect(layout.regions.single.x, 8);
      expect(layout.regions.single.y, 8);
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
          allowResize: false,
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

bool _regionsDoNotOverlap(List<AtlasRegion> regions) {
  for (var first = 0; first < regions.length; first++) {
    for (var second = first + 1; second < regions.length; second++) {
      if (_overlaps(regions[first], regions[second])) return false;
    }
  }
  return true;
}
