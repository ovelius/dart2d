library vec2;

import 'dart:math';

import 'package:dart2d/net/state_updates.pb.dart';

class Vec2 {

  static final Vec2 ZERO = new Vec2();
  static final Vec2 ONE = new Vec2(1, 1);

  static double dotProduct(Vec2 first, Vec2 second) {
    return (first.x * second.x) + (first.y * second.y);
  }

  static Point<int> createIntPointFromVec2(Vec2 vec2) {
    return createIntPoint(vec2.x, vec2.y);
  }

  static Point<int> createIntPoint(double x, double y) {
    return new Point(x.toInt(), y.toInt());
  }

  double x = 0.0;
  double y = 0.0;
  
  Vec2([num? x, y]) {
    this.x = x == null ? 0.0 : x.toDouble();
    this.y = y == null ? 0.0 : y.toDouble();
  }

  Vec2.copy(Vec2 other) {
      this.x = other.x;
      this.y = other.y;
  }

  Vec2.fromProto(Vec2Proto proto) {
    this.x = proto.x;
    this.y = proto.y;
  }
  
  Vec2.random([xmax, ymax]) {
    x = new Random().nextDouble() * xmax;
    y = new Random().nextDouble() * ymax;
  }

  Vec2.fromAngle(double rad, [double scale = 1.0]) {
    x = cos(rad);
    y = sin(rad);
    x *= scale;
    y *= scale;
    }

  operator +(Vec2 other) => new Vec2(x + other.x, y + other.y);
  operator -(Vec2 other) => new Vec2(x - other.x, y - other.y);
  operator *(Vec2 other) => new Vec2(x * other.y, -other.x * y);
  
  double toAngle() {
    return atan2(y, x);
  }

  Point<int> asIntPoint() {
    return createIntPointFromVec2(this);
  }

  Vec2 normalize() {
    double nominator = sum();
    if (nominator == 0.0) {
      return new Vec2();
    }
    return new Vec2(x / nominator, y / nominator);
  }

  double sum() {
    return sqrt(x * x + y * y);
  }

  Vec2 multiply(double factor) {
    return new Vec2(x * factor, y * factor);
  }
  
  Vec2 add(Vec2 other) {
    return new Vec2(x + other.x, y + other.y);
  }

  Vec2 subtract(Vec2 other) {
    return new Vec2(x - other.x, y - other.y);
  }
  
  String toString() {
    return "x: ${x.toStringAsFixed(2)} y: ${y.toStringAsFixed(2)}";
  }

  int get hashCode {
    return x.hashCode + y.hashCode;
  }
  bool operator ==(o) => o is Vec2 && x == o.x && y == o.y;

  Vec2Proto toProto() {
    return Vec2Proto()
      ..y = y
      ..x = x;
  }
}
