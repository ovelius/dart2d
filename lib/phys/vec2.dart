library vec2;

import 'dart:math';

class Vec2 {

  static double dotProduct(Vec2 first, Vec2 second) {
    return (first.x * second.x) + (first.y * second.y);
  }

  double x;
  double y;
  
  Vec2([x, y]) {
    this.x = x == null ? 0.0 : x;
    this.y = y == null ? 0.0 : y;
  }

  Vec2.copy(Vec2 other) {
      this.x = other.x;
      this.y = other.y;
  }
  
  Vec2.random([xmax, ymax]) {
    x = new Random().nextDouble() * xmax;
    y = new Random().nextDouble() * ymax;
  }

  Vec2.fromAngle(double rad, [double scale]) {
    x = cos(rad);
    y = sin(rad);
    if (scale != null) {
      x *= scale;
      y *= scale;
    }
  }

  operator +(Vec2 other) => new Vec2(x + other.x, y + other.y);
  operator -(Vec2 other) => new Vec2(x - other.x, y - other.y);
  operator *(Vec2 other) => new Vec2(x * other.y, -other.x * y);
  
  double toAngle() {
    return atan2(y, x);
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
  
  String toString() {
    return "x: ${x.toStringAsFixed(2)} y: ${y.toStringAsFixed(2)}";
  }
}
