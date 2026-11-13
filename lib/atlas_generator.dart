import 'dart:math' as math;
import 'dart:ui';

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
    this.requiresResize = false,
  });

  final int width;
  final int height;
  final List<AtlasRegion> regions;
  final bool requiresResize;
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
    bool autoFit = true,
    bool allowResize = true,
  }) {
    if (textures.isEmpty) {
      throw const FormatException('Choose at least one texture to pack.');
    }
    if (maxSize < 256 || padding < 0) {
      throw const FormatException('Invalid atlas settings.');
    }
    for (final texture in textures) {
      if (texture.width <= 0 || texture.height <= 0) {
        throw const FormatException('A source texture has invalid dimensions.');
      }
    }

    final dimensions =
        autoFit ? _candidateDimensions(maxSize) : [(maxSize, maxSize)];
    final originalLayout = _tryPackTextures(
      textures,
      dimensions,
      padding,
      1,
    );
    if (originalLayout != null) return originalLayout;
    if (!allowResize) {
      throw _doesNotFit(maxSize, padding);
    }

    final resizeDimensions = [(maxSize, maxSize)];
    var low = 0.0;
    var high = 1.0;
    AtlasLayout? bestLayout;
    for (var iteration = 0; iteration < 24; iteration++) {
      final scale = (low + high) / 2;
      final resizedLayout = _tryPackTextures(
        textures,
        resizeDimensions,
        padding,
        scale,
      );
      if (resizedLayout == null) {
        high = scale;
      } else {
        low = scale;
        bestLayout = resizedLayout;
      }
    }
    if (bestLayout == null) throw _doesNotFit(maxSize, padding);
    return AtlasLayout(
      width: bestLayout.width,
      height: bestLayout.height,
      regions: bestLayout.regions,
      requiresResize: true,
    );
  }

  static FormatException _doesNotFit(int maxSize, int padding) =>
      FormatException(
        'The selected textures do not fit within a $maxSize × $maxSize atlas. '
        '${padding > 0 ? 'Reduce island padding or ' : ''}'
        'increase the maximum size.',
      );

  static AtlasLayout? _tryPackTextures(
    List<AtlasTextureSize> textures,
    List<(int, int)> dimensions,
    int padding,
    double scale,
  ) {
    final packedTextures = [
      for (var index = 0; index < textures.length; index++)
        _PackedTexture(
          index,
          math.max(1, (textures[index].width * scale).round()) + padding * 2,
          math.max(1, (textures[index].height * scale).round()) + padding * 2,
        ),
    ];
    for (final (width, height) in dimensions) {
      for (final compare in _sortOrders) {
        final ordered = [...packedTextures]..sort(compare);
        for (var placementStrategy = 0;
            placementStrategy < 3;
            placementStrategy++) {
          final result = _tryPack(
            ordered,
            width,
            height,
            padding,
            placementStrategy,
          );
          if (result != null) return result;
        }
      }
    }
    return null;
  }

  static final List<int Function(_PackedTexture, _PackedTexture)> _sortOrders =
      [
    (first, second) {
      final byArea = second.width * second.height - first.width * first.height;
      if (byArea != 0) return byArea;
      return math.max(second.width, second.height) -
          math.max(first.width, first.height);
    },
    (first, second) {
      final byWidth = second.width - first.width;
      return byWidth != 0 ? byWidth : second.height - first.height;
    },
    (first, second) {
      final byHeight = second.height - first.height;
      return byHeight != 0 ? byHeight : second.width - first.width;
    },
    (first, second) {
      final firstLongest = math.max(first.width, first.height);
      final secondLongest = math.max(second.width, second.height);
      final byLongest = secondLongest - firstLongest;
      if (byLongest != 0) return byLongest;
      return second.width * second.height - first.width * first.height;
    },
  ];

  static List<(int, int)> _candidateDimensions(int maxSize) {
    final sizes = <int>[];
    for (var size = 256; size <= maxSize; size *= 2) {
      sizes.add(size);
      if (size > maxSize ~/ 2) break;
    }
    if (!sizes.contains(maxSize)) sizes.add(maxSize);
    return [for (final size in sizes) (size, size)];
  }

  static AtlasLayout? _tryPack(
    List<_PackedTexture> textures,
    int width,
    int height,
    int padding,
    int placementStrategy,
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
        final primaryScore = switch (placementStrategy) {
          0 => shortFit,
          1 => free.area - texture.width * texture.height,
          _ => free.y + texture.height,
        };
        final secondaryScore = switch (placementStrategy) {
          0 => longFit,
          1 => shortFit,
          _ => free.x,
        };
        if (best == null ||
            primaryScore < best.shortFit ||
            (primaryScore == best.shortFit && secondaryScore < best.longFit)) {
          best = _Placement(
            _Rect(free.x, free.y, texture.width, texture.height),
            primaryScore,
            secondaryScore,
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
