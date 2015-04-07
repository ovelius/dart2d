import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/phys/vec2.dart';
import 'dart:math';
import 'dart:html';

class Particles extends Sprite {
  
  Vec2 velocityBase;
  double radius;
  int particleLifeTime;
  List<_Particle> particles;
  Sprite follow;
  Vec2 location;

  Particles(this.follow, this.location, this.velocityBase, [double radius = 10.0, int count = 30, int lifeTime = 35]) :
      super(0.0, 0.0, 0, 1, 1) {
    this.lifeTime = lifeTime;
    Random r = new Random();
    particles = new List();
    for (int i = 0; i < count; i++) {
      _Particle p = new _Particle();
      p.setToRandom(r, radius, follow, location, velocityBase, lifeTime);
      particles.add(p);
    }
    this.radius = radius;
    this.particleLifeTime = lifeTime;
  }

  frame(double duration, int frames, [Vec2 gravity]) {
    for(var i = 0; i < particles.length; i++) {
      _Particle p = particles[i];
      if(p.lifeTimeRemaining < 0 || p.radius < 0) {
        continue;
      }
      p.location.x += p.speed.x * duration;
      p.location.y += p.speed.y * duration;
      if (gravity != null) {
        p.location += gravity.multiply(duration * 0.1);
      }
    }
  }
  draw(CanvasRenderingContext2D context, bool debug, [Vec2 translate]) {
    int dead = 0;
    if (translate != null) {
      context.translate(translate.x, translate.y);
    }
    Random r = new Random();
    context.globalCompositeOperation = "lighter";
    for(var i = 0; i < particles.length; i++) {
      _Particle p = particles[i];
      
      
      //regenerate particles
      if(p.lifeTimeRemaining < 0 || p.radius < 0) {
        if (follow != null && !follow.remove) {
          p.setToRandom(r, radius, follow, location, velocityBase, this.particleLifeTime);
        } else {
          dead++;
        }
        continue;
      }
      
      context.beginPath();
      double opacity = (p.lifeTimeRemaining / this.particleLifeTime * 100).round() / 100.0;
      var gradient = context.createRadialGradient(p.location.x, p.location.y, 0, p.location.x, p.location.y, p.radius);
      var color = "rgba(${p.r}, ${p.g}, ${p.b}, ${opacity})";
      gradient.addColorStop(0, color);
      gradient.addColorStop(0.5, color);
      gradient.addColorStop(1, "rgba(${p.r}, ${p.g}, ${p.b}, 0)");
      context.fillStyle = gradient;
      context.arc(p.location.x, p.location.y, p.radius, 0, PI*2.0);
      context.fill();
      
      p.lifeTimeRemaining--;
      p.radius--;
     
    }
    if (dead == particles.length) {
      this.remove = true;
    }
  }
}

class _Particle {
  Vec2 location;
  Vec2 speed;
  int lifeTimeRemaining;
  int r, g, b;
  int radius;
  
  setToRandom(Random ra, double radius, Sprite follow, Vec2 location, Vec2 velocityBase, int lifeTime) {
    r = ra.nextInt(255);
    g = ra.nextInt(255);
    b = ra.nextInt(255);
    this.radius = (radius * ra.nextDouble()).toInt();
    if (follow != null) {
      this.location = follow.centerPoint();
    } else {
      this.location = location;
    }
    speed = new Vec2(ra.nextDouble() * velocityBase.x, ra.nextDouble() * velocityBase.y);
    lifeTimeRemaining = ra.nextInt(lifeTime);
  }
}