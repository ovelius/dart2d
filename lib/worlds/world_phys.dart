import 'dart:math';
import 'package:dart2d/worlds/byteworld.dart';
import 'package:dart2d/sprites/destructoid.dart';
import 'package:dart2d/worlds/worm_world.dart';

class _pos { 
  _pos(this.x, this.y);
  int x;
  int y;
  
  void checkUpperLeft(int x, int y) {
    this.x = min(this.x, x);
    this.y = min(this.y, y);
  }

  void checkBottomRight(int x, int y) {
    this.x = max(this.x, x);
    this.y = max(this.y, y);
  }
}

class WorldPhys {
  static const UP = 0;
  static const DOWN = 1;
  static const LEFT = 2;
  static const RIGHT = 3;
  
  static final List<int> _dx = [-1, 0, 0, 1];
  static final List<int> _dy = [0, -1, 1, 0];
  
  static void lookAround(WormWorld world, double x, double y, double radius) {
    Map connected = isConnected(world.byteWorld, (x - radius).toInt(), (y - radius).toInt());
    print("IsConnected: ${connected}");
    if (connected != null) {
      Destructoid d = new Destructoid(world.byteWorld, null /*world.centerView*/,
          connected['x'], connected['y'],  connected['x2'], connected['y2']);
      world.byteWorld.clearAtRect(
          d.position.x.toInt(), d.position.y.toInt(), d.size.x.toInt(), d.size.y.toInt());
      world.addSprite(d);
    }
  } 
    
  static Map isConnected(ByteWorld world, int x, int y) {
    world.canvas.context2D.fillStyle = "#ffffff";
    int width = world.width;
    Set<int> visited = new Set();
    List<int> backlog = new List();
    backlog.add(x + y * width);
    visited.add(x + y * width);
    _pos bottomRight = new _pos(x, y);
    _pos upperLeft = new _pos(x, y);
        
    while (backlog.length > 0) {
      int i = backlog.removeLast();
      int bx = i % width;
      int by = i ~/ width;
      
      // Hit a wall.
      if (_endCondition(world, bx, by)) {
        return null;
      }
      
      if (backlog.length > 5000) {
        return null;
      }
      
      if (bx != x || by != y) {
        world.canvas.context2D.fillStyle = "rgba(255,0,0,255)";
        world.canvas.context2D.fillRect(bx, by, 1, 1);
      }
      
      upperLeft.checkUpperLeft(bx, by);
      bottomRight.checkBottomRight(bx, by);
      
      if (backlog.length % 10 == 0) {
        print("at ${bx} ${by} visited ${visited.length} backlog: ${backlog.length}");
      }
      
      for (int i = 0; i < 4; i++) {
        int nx = bx + _dx[i];
        int ny = by + _dy[i];
        int value = nx + ny * width;        
        if (!visited.contains(value) && _shouldInclude(world, nx, ny)) {
          visited.add(value);
          backlog.add(value);
        }
      }
    }
    
    if (upperLeft.x == bottomRight.x) {
      return null;
    }
    if (upperLeft.y == bottomRight.y) {
      return null;
    }
    
    return {
      'x': upperLeft.x, 'y': upperLeft.y,
      'x2': bottomRight.x,  'y2': bottomRight.y + 1
    };
  }
  
  static bool _shouldInclude(ByteWorld world, int x, int y) {
    return world.canvas.context2D.getImageData(x, y, 1, 1).data[3] > 0;
  }
  
  static bool _endCondition(ByteWorld world, int x, int y) {
    return y <= 0 || x <= 0 || x >= world.width - 1 || y >= world.height - 1;
  }
  
  
  /**
   * Walks the world at origin position and attemps to find a bounding box of the world canvas that
   * doesn't end in an edge.
   * 
   * In case we hit the edge we return null.
   */
  static Map worldBoundedBox(ByteWorld world, int x, int y) {
    // TODO: Special case: What if we start in the upper right corner.
    _pos pos = new _pos(x, y);
    _pos bottomRight = new _pos(x, y);
    _pos upperLeft = new _pos(x, y);

    List<bool> exhaustedDirections = [false, false, false, false];
    
    nextPos(world, pos, exhaustedDirections);
    upperLeft.checkUpperLeft(pos.x, pos.y);
    bottomRight.checkBottomRight(pos.x, pos.y);

    while ( !_endCondition(world, pos.x, pos.y)) {
      if (pos.x == bottomRight.x && pos.y == upperLeft.y) {
        // We are in the upper right corner, terminate.
        return {
          'x': upperLeft.x, 'y': upperLeft.y,
          'x2': bottomRight.x,  'y2': bottomRight.y
        };
      }
      nextPos(world, pos, exhaustedDirections);
      upperLeft.checkUpperLeft(pos.x, pos.y);
      bottomRight.checkBottomRight(pos.x, pos.y);
    }
    return null;
  }
  
  /**
   * Walk clockwise.
   * We should en up in the upper right corner.
   */
  static void nextPos(ByteWorld world, _pos pos, List<bool> exhaustedDirections) {
    // Try down first.
    if (!exhaustedDirections[DOWN] && _shouldInclude(world, pos.x, pos.y + 1)) {
      pos.y+=1;
      print("moved down to ${pos.x} ${pos.y}");
      return;
    }
    // Next try left.
    if (!exhaustedDirections[LEFT] && _shouldInclude(world, pos.x - 1, pos.y)) {
      pos.x-=1;
      print("moved left to ${pos.x} ${pos.y}");
      return;
    }
    // Next try up.
    // After going up we are not allowed to go down again.
    if (_shouldInclude(world, pos.x, pos.y - 1)) {
      pos.y-=1;
      exhaustedDirections[DOWN] = true;
      print("moved up to ${pos.x} ${pos.y}");
      return;
    }
    // Finally right.
    // Then we are not allowed to go left again.
    if (_shouldInclude(world, pos.x + 1, pos.y)) {
      pos.x+=1;
      print("moved right to ${pos.x} ${pos.y}");
      exhaustedDirections[LEFT] = true;
      return;
    }
  }
}