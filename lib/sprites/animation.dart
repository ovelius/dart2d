library stickysprite;

import 'sprite.dart';
import 'dart:math';
import 'dart:html';
import 'package:dart2d/phys/vec2.dart';

/*
 * A sprite that follows the position of another sprite. 
 */
class Explosion extends Sprite {

  double duration;
  Vec2 centerLocation;
  double radius;
  int magnitude;
  
  Explosion(Vec2 location, double radius, [double duration = 0.4, int magnitude = 2]) :
      super(location.x, location.y, 0, 1, 1) {
    this.spriteType = SpriteType.CUSTOM;
    this.duration = duration;
    double size = radius / 1.4142; // sqrt 2
    this.size.x = size;
    this.size.y = size;
    this.radius = radius;
    centerLocation = location;
    this.setCenter(centerLocation);
    this.magnitude = magnitude;
  }

  frame(double duration, int frameStep, [Vec2 gravity]) {
    radius = radius * (1.0 - (duration * 2.00));
    this.setCenter(centerLocation);
    this.duration -= duration;
    if (this.duration < 0) {
      this.remove = true;
    }
    super.frame(duration, frames);
  }
  
  draw(CanvasRenderingContext2D context, bool debug, [Vec2 translate]) {
    context.translate(translate.x, translate.y);
    Random ra = new Random();
    double x = position.x - this.radius + this.radius * 2 * ra.nextDouble();
    double y = position.y - this.radius + this.radius * 2 * ra.nextDouble();
    double radius = ra.nextDouble() * this.radius;
    context.globalCompositeOperation = "lighter";
    for(var i = 0; i < magnitude; i++) {
      context.beginPath();
      double opacity = ra.nextDouble();
      var gradient = context.createRadialGradient(x, y, 0, x, y, radius);
      int r = ra.nextInt(255);
      int g = ra.nextInt(255);
      int b = ra.nextInt(255);
      var color = "rgba(${r}, ${g}, ${b}, ${opacity})";
      gradient.addColorStop(0, color);
      gradient.addColorStop(0.5, color);
      gradient.addColorStop(1, "rgba(${r}, ${g}, ${b}, 0)");
      context.fillStyle = gradient;
      context.arc(x, y, radius, 0, PI*2.0);
      context.fill();
    }
  }
}