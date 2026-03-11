import 'package:dart2d/sprites/sprites.dart';

class SpatialGrid {
  final double cellSize;
  final Map<int, List<Sprite>> _grid = {};

  SpatialGrid(this.cellSize);

  void clear() {
    _grid.clear();
  }

  void insert(Sprite sprite) {
    int x1 = (sprite.position.x / cellSize).floor();
    int y1 = (sprite.position.y / cellSize).floor();
    int x2 = ((sprite.position.x + sprite.size.x) / cellSize).floor();
    int y2 = ((sprite.position.y + sprite.size.y) / cellSize).floor();

    for (int x = x1; x <= x2; x++) {
      for (int y = y1; y <= y2; y++) {
        int key = _hash(x, y);
        _grid.putIfAbsent(key, () => []).add(sprite);
      }
    }
  }

  Iterable<Sprite> query(Sprite sprite) {
    int x1 = (sprite.position.x / cellSize).floor();
    int y1 = (sprite.position.y / cellSize).floor();
    int x2 = ((sprite.position.x + sprite.size.x) / cellSize).floor();
    int y2 = ((sprite.position.y + sprite.size.y) / cellSize).floor();

    Set<Sprite> result = {};
    for (int x = x1; x <= x2; x++) {
      for (int y = y1; y <= y2; y++) {
        int key = _hash(x, y);
        List<Sprite>? cell = _grid[key];
        if (cell != null) {
          result.addAll(cell);
        }
      }
    }
    result.remove(sprite);
    return result;
  }

  Iterable<Sprite> queryArea(double xCenter, double yCenter, double radius) {
    int x1 = ((xCenter - radius) / cellSize).floor();
    int y1 = ((yCenter - radius) / cellSize).floor();
    int x2 = ((xCenter + radius) / cellSize).floor();
    int y2 = ((yCenter + radius) / cellSize).floor();

    Set<Sprite> result = {};
    for (int x = x1; x <= x2; x++) {
      for (int y = y1; y <= y2; y++) {
        int key = _hash(x, y);
        List<Sprite>? cell = _grid[key];
        if (cell != null) {
          result.addAll(cell);
        }
      }
    }
    return result;
  }

  int _hash(int x, int y) {
    // A simple hash function for grid coordinates.
    // Using a large prime to spread out the values.
    return x * 73856093 ^ y * 19349663;
  }

  String toString() {
    return "SpatialGrid[$cellSize] - sprites - ${_grid}";
  }
}
