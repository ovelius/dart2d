
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/net/state_updates.dart';
import 'dart:math';

class Particles extends MovingSprite {
  static const COLORFUL = 1;
  static const FIRE = 2;

  double radius;
  int particleLifeTime;
  List<_Particle> particles;
  Sprite follow;
  int followId;
  int particleType;
  double shrinkPerStep;
  // If we should explode.
  int damage = null;
  WormWorld world;
  // We got it from network.
  bool sendToNetwork = false;

  LocalPlayerSprite owner;

  Particles(WormWorld world, Sprite follow, Vec2 position, Vec2 velocityBase,
      [double radius = 10.0, int count = 30, int lifeTime = 35, shrinkPerStep = 1.0, int particleType = COLORFUL]) :
      super(position, new Vec2(1, 1), SpriteType.CUSTOM) {
    this.follow = follow;
    this.velocity = velocityBase;
    this.lifeTime = lifeTime;
    this.particleType = particleType;
    this.shrinkPerStep = shrinkPerStep;
    this.networkType = NetworkType.LOCAL_ONLY;
    this.invisibleOutsideCanvas = false;
    this.collision = false;
    Random r = new Random();
    particles = new List();
    for (int i = 0; i < count; i++) {
      _Particle p = new _Particle();
      p.setToRandom(r, radius, follow, position, velocityBase, lifeTime);
      particles.add(p);
    }
    this.radius = radius;
    this.particleLifeTime = lifeTime;
  }
  
  Particles.fromNetworkUpdate(List<int> data, WormWorld world)
      : super(new Vec2(), new Vec2(1, 1),  SpriteType.CUSTOM) {
    this.position = new Vec2(data[0] / DOUBLE_INT_CONVERSION, data[1] / DOUBLE_INT_CONVERSION);
    this.velocity = new Vec2(data[2] / DOUBLE_INT_CONVERSION, data[3] / DOUBLE_INT_CONVERSION);
    this.radius = data[4] / DOUBLE_INT_CONVERSION;
    this.particleLifeTime = data[5];
    this.particleType = data[6];
    this.shrinkPerStep = data[7] / DOUBLE_INT_CONVERSION;
    int count = data[8];
    this.lifeTime = data[9];
    if (data.length > 10) {
      this.followId = data[10];
    }
    this.networkType = NetworkType.LOCAL_ONLY;
    this.invisibleOutsideCanvas = false;
    Random r = new Random();
    particles = new List();
    for (int i = 0; i < count; i++) {
       _Particle p = new _Particle();
       p.setToRandom(r, radius, follow, position, velocity, lifeTime);
       particles.add(p);
    }
    this.world = world;
  }
  
  List<int> toNetworkUpdate() {
    List<int> list = [
        position.x * DOUBLE_INT_CONVERSION,
        position.y * DOUBLE_INT_CONVERSION,
        velocity.x * DOUBLE_INT_CONVERSION,
        velocity.y * DOUBLE_INT_CONVERSION,
        radius * DOUBLE_INT_CONVERSION,
        particleLifeTime,
        particleType, 
        shrinkPerStep * DOUBLE_INT_CONVERSION,
        particles.length,
        lifeTime,
      ];
    if (follow != null) {
      list.add(follow.networkId);
    }
    return list;
  }

  frame(double duration, int frames, [Vec2 gravity]) {
    Vec2 g = gravity.multiply(duration * 0.1);
    if (followId != null && follow == null
        && world.spriteIndex[followId] != null) {
      follow = world.spriteIndex[followId];
      followId = null;
    }
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
      p.lifeTimeRemaining--;
      p.radius-=shrinkPerStep;
    }
    super.frame(duration, frames, Vec2.ZERO);
  }
  draw(var /*CanvasRenderingContext2D*/ context, bool debug) {
    int dead = 0;
    Random r = new Random();
    context.globalCompositeOperation = "lighter";
    for(var i = 0; i < particles.length; i++) {
      _Particle p = particles[i];
      if(p.lifeTimeRemaining < 0 || p.radius < 0) {
        if (follow != null && !follow.remove) {
          p.setToRandom(r, radius, follow, position, velocity, this.particleLifeTime);
        } else {
          dead++;
        }
        continue;
      }
      
      context.beginPath();
      setFillStyle(context, p);
      context.arc(p.location.x, p.location.y, p.radius, 0, PI*2.0);
      context.fill();  
    }
    if (dead == particles.length) {
      this.remove = true;
    }
  }
  
  setFillStyle(var /*CanvasRenderingContext2D*/ context, _Particle p) {
    if (this.particleType == COLORFUL) {
      double opacity = (p.lifeTimeRemaining / this.particleLifeTime * 100).round() / 100.0;
      var /*CanvasGradient*/ gradient = context.createRadialGradient(
          p.location.x, p.location.y, 0, p.location.x, p.location.y, p.radius);
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

  collide(MovingSprite other, var unused, int direction) {
    if (!world.network().isCommander()) {
      return;
    }
    if (other != null && damage != null && other.takesDamage() &&  other.networkId != owner.networkId) {
      other.takeDamage(damage, owner);
      lifeTime = 0;
    } else if (direction != null && direction != 0 && damage != null) {
      world.explosionAt(centerPoint(), null, damage, radius * 1.5, owner);
      lifeTime = 0;
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