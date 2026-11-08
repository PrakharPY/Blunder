import 'dart:math' as math;
import 'dart:ui';

enum AtlasShape { square, landscape, portrait }

class AtlasTextureSize {
  const AtlasTextureSize(this.width, this.height);

  final int width;
  final int height;
}

class AtlasRegion {
  const AtlasRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;
}

class AtlasLayout {
  const AtlasLayout({
    required this.width,
    required this.height,
    required this.regions,
  });

  final int width;
  final int height;
  final List<AtlasRegion> regions;
}

class AtlasTextureRegistry<T> {
  final Map<Object, int> _indices = {};
  final List<T?> textures = [];

  int indexFor(Object key, T? texture) {
    final existing = _indices[key];
    if (existing != null) return existing;
    final index = textures.length;
    _indices[key] = index;
    textures.add(texture);
    return index;
  }
}

class _Rect {
  const _Rect(this.x, this.y, this.width, this.height);

  final int x;
  final int y;
  final int width;
  final int height;

  int get right => x + width;
  int get bottom => y + height;
  int get area => width * height;

  bool contains(_Rect other) =>
      x <= other.x &&
      y <= other.y &&
      right >= other.right &&
      bottom >= other.bottom;

  bool intersects(_Rect other) =>
      x < other.right &&
      right > other.x &&
      y < other.bottom &&
      bottom > other.y;
}

class _PackedTexture {
  const _PackedTexture(this.index, this.width, this.height);

  final int index;
  final int width;
  final int height;
}

class _Placement {
  const _Placement(this.rect, this.shortFit, this.longFit);

  final _Rect rect;
  final int shortFit;
  final int longFit;
}

class AtlasPacker {
  const AtlasPacker._();

  static AtlasLayout pack({
    required List<AtlasTextureSize> textures,
    required int maxSize,
    required int padding,
    required AtlasShape shape,
    double density = 1,
    bool autoFit = true,
  }) {
    if (textures.isEmpty) {
      throw const FormatException('Choose at least one texture to pack.');
    }
    if (maxSize < 256 || padding < 0 || !density.isFinite || density <= 0) {
      throw const FormatException('Invalid atlas settings.');
    }
    for (final texture in textures) {
      if (texture.width <= 0 || texture.height <= 0) {
        throw const FormatException('A source texture has invalid dimensions.');
      }
    }

    final packedTextures = [
      for (var index = 0; index < textures.length; index++)
        _PackedTexture(
          index,
          math.max(1, (textures[index].width * density).round()) + padding * 2,
          math.max(1, (textures[index].height * density).round()) + padding * 2,
        ),
    ]..sort((first, second) {
        final byArea =
            second.width * second.height - first.width * first.height;
        if (byArea != 0) return byArea;
        return math.max(second.width, second.height) -
            math.max(first.width, first.height);
      });

    final dimensions = autoFit
        ? _candidateDimensions(maxSize, shape)
        : [
            switch (shape) {
              AtlasShape.square => (maxSize, maxSize),
              AtlasShape.landscape => (maxSize, maxSize ~/ 2),
              AtlasShape.portrait => (maxSize ~/ 2, maxSize),
            },
          ];
    for (final (width, height) in dimensions) {
      final result = _tryPack(packedTextures, width, height, padding);
      if (result != null) return result;
    }
    throw FormatException(
      'The selected textures do not fit within a $maxSize × $maxSize atlas. '
      'Increase the maximum size, lower texture density, or reduce padding.',
    );
  }

  static List<(int, int)> _candidateDimensions(
    int maxSize,
    AtlasShape shape,
  ) {
    final sizes = <int>[];
    for (var size = 256; size <= maxSize; size *= 2) {
      sizes.add(size);
      if (size > maxSize ~/ 2) break;
    }
    if (!sizes.contains(maxSize)) sizes.add(maxSize);
    final result = <(int, int)>[];
    for (final width in sizes) {
      for (final height in sizes) {
        final matches = switch (shape) {
          AtlasShape.square => width == height,
          AtlasShape.landscape => width >= height,
          AtlasShape.portrait => height >= width,
        };
        if (matches) result.add((width, height));
      }
    }
    result.sort((first, second) {
      final areaOrder = first.$1 * first.$2 - second.$1 * second.$2;
      if (areaOrder != 0) return areaOrder;
      return switch (shape) {
        AtlasShape.square => first.$1.compareTo(second.$1),
        AtlasShape.landscape =>
          (second.$1 - second.$2).compareTo(first.$1 - first.$2),
        AtlasShape.portrait =>
          (second.$2 - second.$1).compareTo(first.$2 - first.$1),
      };
    });
    return result;
  }

  static AtlasLayout? _tryPack(
    List<_PackedTexture> textures,
    int width,
    int height,
    int padding,
  ) {
    final freeRects = <_Rect>[_Rect(0, 0, width, height)];
    final packedRegions = List<AtlasRegion?>.filled(textures.length, null);
    for (final texture in textures) {
      _Placement? best;
      for (final free in freeRects) {
        if (texture.width > free.width || texture.height > free.height) {
          continue;
        }
        final remainingWidth = free.width - texture.width;
        final remainingHeight = free.height - texture.height;
        final shortFit = math.min(remainingWidth, remainingHeight);
        final longFit = math.max(remainingWidth, remainingHeight);
        if (best == null ||
            shortFit < best.shortFit ||
            (shortFit == best.shortFit && longFit < best.longFit)) {
          best = _Placement(
            _Rect(free.x, free.y, texture.width, texture.height),
            shortFit,
            longFit,
          );
        }
      }
      if (best == null) return null;

      packedRegions[texture.index] = AtlasRegion(
        x: best.rect.x + padding,
        y: best.rect.y + padding,
        width: texture.width - padding * 2,
        height: texture.height - padding * 2,
      );
      _splitFreeRects(freeRects, best.rect);
    }
    return AtlasLayout(
      width: width,
      height: height,
      regions: [for (final region in packedRegions) region!],
    );
  }

  static void _splitFreeRects(List<_Rect> freeRects, _Rect used) {
    final additions = <_Rect>[];
    for (final free in freeRects) {
      if (!free.intersects(used)) continue;
      if (used.x > free.x) {
        additions.add(_Rect(free.x, free.y, used.x - free.x, free.height));
      }
      if (used.right < free.right) {
        additions.add(
          _Rect(used.right, free.y, free.right - used.right, free.height),
        );
      }
      if (used.y > free.y) {
        additions.add(_Rect(free.x, free.y, free.width, used.y - free.y));
      }
      if (used.bottom < free.bottom) {
        additions.add(
          _Rect(free.x, used.bottom, free.width, free.bottom - used.bottom),
        );
      }
    }
    freeRects
      ..removeWhere((free) => free.intersects(used))
      ..addAll(additions);
    for (var first = 0; first < freeRects.length; first++) {
      for (var second = first + 1; second < freeRects.length;) {
        if (freeRects[first].contains(freeRects[second])) {
          freeRects.removeAt(second);
        } else if (freeRects[second].contains(freeRects[first])) {
          freeRects.removeAt(first);
          first--;
          break;
        } else {
          second++;
        }
      }
    }
  }

  static Offset remapUv({
    required Offset uv,
    required AtlasTextureSize source,
    required AtlasRegion region,
    required AtlasLayout atlas,
  }) {
    final u = uv.dx.clamp(0.0, 1.0) * source.width;
    final v = uv.dy.clamp(0.0, 1.0) * source.height;
    return Offset(
      (region.x + u * region.width / source.width) / atlas.width,
      1 -
          (region.y + (source.height - v) * region.height / source.height) /
              atlas.height,
    );
  }
}
