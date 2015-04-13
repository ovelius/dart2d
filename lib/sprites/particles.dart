library particles;

import 'package:dart2d/sprites/sprite.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'dart:math';
import 'dart:html';

class Particles extends Sprite {
  static const COLORFUL = 1;
  static const FIRE = 2;

  Vec2 velocityBase;
  double radius;
  int particleLifeTime;
  List<_Particle> particles;
  Sprite follow;
  Vec2 location;
  int particleType;
  double shrinkPerStep;
  // If we should explode.
  int damage = null;
  WormWorld world;
  
  Particles(this.follow, this.location, this.velocityBase,
      [double radius = 10.0, int count = 30, int lifeTime = 35, shrinkPerStep = 1.0, int particleType = COLORFUL]) :
      super(0.0, 0.0, 0, 1, 1) {
    this.lifeTime = lifeTime;
    this.particleType = particleType;
    this.shrinkPerStep = shrinkPerStep;
    this.networkType = NetworkType.LOCAL_ONLY;
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
    Vec2 g = gravity.multiply(duration * 0.1);
    for(var i = 0; i < particles.length; i++) {
      _Particle p = particles[i];
      if(p.lifeTimeRemaining < 0 || p.radius < 0) {
        continue;
      }
      p.location.x += p.speed.x * duration;
      p.location.y += p.speed.y * duration;
      if (gravity != null && this.particleType != FIRE) {
        p.location += g;
      }
      if (damage != null) {
        if (world.byteWorld.isCanvasCollide(p.location.x, p.location.y)) {
          world.explosionAt(p.location, null, damage, radius);
          p.lifeTimeRemaining = 0;
        }
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
      if(p.lifeTimeRemaining < 0 || p.radius < 0) {
        if (follow != null && !follow.remove) {
          p.setToRandom(r, radius, follow, location, velocityBase, this.particleLifeTime);
        } else {
          dead++;
        }
        continue;
      }
      
      context.beginPath();
      setFillStyle(context, p);
      context.arc(p.location.x, p.location.y, p.radius, 0, PI*2.0);
      context.fill();
      
      // TODO: Double and decrement in world loop.
      p.lifeTimeRemaining--;
      p.radius-=shrinkPerStep;
     
    }
    if (dead == particles.length) {
      this.remove = true;
    }
  }
  
  setFillStyle(CanvasRenderingContext2D context, _Particle p) {
    if (this.particleType == COLORFUL) {
      double opacity = (p.lifeTimeRemaining / this.particleLifeTime * 100).round() / 100.0;
      CanvasGradient gradient = context.createRadialGradient(p.location.x, p.location.y, 0, p.location.x, p.location.y, p.radius);                
      String color = "rgba(${p.r},${p.g},${p.b},${opacity})";
      String colorTransparent = "rgba(${p.r},${p.g},${p.b},0)";
      gradient.addColorStop(0, color);
      gradient.addColorStop(0.5, color);
      gradient.addColorStop(1, colorTransparent);
      context.fillStyle = gradient;   
    } else if (this.particleType == FIRE) {
      double lifePercentage = p.lifeTimeRemaining / this.particleLifeTime;
      double lifePercentageInverse = 1.0 - lifePercentage;   
      String color = 
          "rgba(${(260 * lifePercentage).toInt()}, ${(10 * lifePercentageInverse).toInt()}, ${(10 * lifePercentageInverse).toInt()}, ${lifePercentageInverse})";
      context.fillStyle = color;
    } 
  }
}

class _Particle {
  Vec2 location;
  Vec2 speed;
  int lifeTimeRemaining;
  int r, g, b;
  double radius;
  
  setToRandom(Random ra, double radius, Sprite follow, Vec2 location, Vec2 velocityBase, int lifeTime) {
    r = ra.nextInt(255);
    g = ra.nextInt(255);
    b = ra.nextInt(255);
    this.radius = (radius * ra.nextDouble());
    if (follow != null) {
      this.location = follow.centerPoint();
    } else {
      this.location = new Vec2.copy(location);
    }
    double sum = velocityBase.sum();
    speed = new Vec2(
        velocityBase.x + sum * ra.nextDouble() * 0.1 - sum * ra.nextDouble() * 0.1,
        velocityBase.y + sum * ra.nextDouble() * 0.1 - sum * ra.nextDouble() * 0.1);
    lifeTimeRemaining = ra.nextInt(lifeTime);
  }
}