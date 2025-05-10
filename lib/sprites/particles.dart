
import 'dart:js_interop';

import 'package:dart2d/net/state_updates.pb.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/phys/vec2.dart';
import 'package:dart2d/sprites/sprites.dart';
import 'package:dart2d/worlds/worm_world.dart';
import 'package:dart2d/net/state_updates.dart';
import 'dart:math';
import 'package:web/web.dart';

class Particles extends MovingSprite {
  final Set<ParticleEffects_ParticleType> RANDOM_VELOCITY_PARTICLES =
      Set.of([ParticleEffects_ParticleType.CONFETTI, ParticleEffects_ParticleType.BLOOD]);
  late double radius;
  late int particleLifeTime;
  List<_Particle> particles = [];
  Sprite? follow;
  Vec2? followOffset = null;
  int? followId;
  late ParticleEffects_ParticleType particleType;
  late double shrinkPerStep;
  // If we should explode.
  int? damage = null;
  late WormWorld world;
  // We got it from network.
  bool sendToNetwork = false;

  LocalPlayerSprite? owner;

  Particles(WormWorld world, Sprite? follow, Vec2 position, Vec2 velocityBase,
  {Vec2? followOffset, double radius = 10.0, int count = 30, int lifeTime = 35, shrinkPerStep = 1.0, ParticleEffects_ParticleType particleType = ParticleEffects_ParticleType.COLORFUL}) :
      super(position, new Vec2(1, 1), SpriteType.CUSTOM) {
    this.follow = follow;
    this.velocity = velocityBase;
    this.lifeTime = lifeTime;
    this.particleType = particleType;
    this.shrinkPerStep = shrinkPerStep;
    this.followOffset = followOffset;
    this.networkType = NetworkType.LOCAL_ONLY;
    this.invisibleOutsideCanvas = false;
    this.collision = false;
    Random r = new Random();
    for (int i = 0; i < count; i++) {
      _Particle p = new _Particle();
      p.setToRandom(r, radius, follow, followOffset, position, velocityBase, lifeTime,
          RANDOM_VELOCITY_PARTICLES.contains(particleType));
      particles.add(p);
    }
    this.radius = radius;
    this.particleLifeTime = lifeTime;
  }
  
  Particles.fromNetworkUpdate(ParticleEffects data, WormWorld world)
      : super(new Vec2(), new Vec2(1, 1),  SpriteType.CUSTOM) {
    this.position = Vec2.fromProto(data.position);
    this.velocity = Vec2.fromProto(data.velocity);
    this.radius = data.radius;
    this.particleLifeTime = data.lifetimeFrames;
    this.particleType = data.particleType;
    this.shrinkPerStep = data.shrinkPerStep;
    int count = data.particleCount;
    this.lifeTime = data.spriteLifetimeFrames;
    this.followOffset = Vec2.fromProto(data.followOffset);
    if (data.hasFollowId()) {
      this.followId = data.followId;
    }
    this.networkType = NetworkType.LOCAL_ONLY;
    this.invisibleOutsideCanvas = false;
    Random r = new Random();
    for (int i = 0; i < count; i++) {
       _Particle p = new _Particle();
       p.setToRandom(r, radius, follow, followOffset, position, velocity,  particleLifeTime,
           RANDOM_VELOCITY_PARTICLES.contains(particleType));
       particles.add(p);
    }
    this.world = world;
  }
  
  ParticleEffects toNetworkUpdate() {
    ParticleEffects particle = ParticleEffects()
      ..position = position.toProto()
      ..velocity = velocity.toProto()
      ..radius = radius
      ..lifetimeFrames = particleLifeTime
      ..spriteLifetimeFrames = lifeTime
      ..particleType = particleType
      ..shrinkPerStep = shrinkPerStep
      ..particleCount = particles.length
      ..lifetimeFrames = lifeTime;

    if (followOffset != null) {
      particle.followOffset = followOffset!.toProto();
    }
    if (follow != null) {
      particle.followId = follow!.networkId!;
    }
    return particle;
  }

  frame(double duration, int frames, [Vec2? gravity]) {
    Vec2? g = gravity == null ? null : gravity.multiply(duration * 0.1);
    if (followId != null && follow == null
        && world.spriteIndex[followId] != null) {
      follow = world.spriteIndex[followId];
      followId = null;
    }
    for(var i = 0; i < particles.length; i++) {
      _Particle p = particles[i];
      p.location.x += p.speed.x * duration;
      p.location.y += p.speed.y * duration;
      if(p.lifeTimeRemaining < 0 || p.radius < 0) {
        continue;
      }
      if (g != null) {
        if (this.particleType != ParticleEffects_ParticleType.FIRE) {
          p.location += g;
        }
        if (RANDOM_VELOCITY_PARTICLES.contains(particleType)) {
          p.speed += g.multiply(6.0);
        }
      }
      p.lifeTimeRemaining--;
      p.radius-=shrinkPerStep;
    }
    super.frame(duration, frames, Vec2.ZERO);
  }
  draw(CanvasRenderingContext2D context, bool debug) {
    int dead = 0;
    Random r = new Random();
    if (particleType != ParticleEffects_ParticleType.SODA
     && particleType != ParticleEffects_ParticleType.BLOOD) {
      context.globalCompositeOperation = "lighter";
    }
    for(var i = 0; i < particles.length; i++) {
      _Particle p = particles[i];
      if(p.lifeTimeRemaining < 0 || p.radius < 0) {
        if (follow != null && !follow!.remove) {
          p.setToRandom(r, radius, follow, followOffset, position, velocity, this.particleLifeTime,
             RANDOM_VELOCITY_PARTICLES.contains(particleType));
        } else {
          dead++;
        }
        continue;
      }
      
      context.beginPath();
      setFillStyle(context, p, r);
      context.arc(p.location.x, p.location.y, p.radius, 0, pi*2.0);
      context.fill();  
    }
    if (dead == particles.length) {
      this.remove = true;
    }
  }
  
  setFillStyle(CanvasRenderingContext2D context, _Particle p, Random r) {
    if (this.particleType == ParticleEffects_ParticleType.COLORFUL) {
      double opacity = (p.lifeTimeRemaining / this.particleLifeTime * 100).round() / 100.0;
      CanvasGradient gradient = context.createRadialGradient(
          p.location.x, p.location.y, 0, p.location.x, p.location.y, p.radius);
      String color = "rgba(${p.r},${p.g},${p.b},${opacity})";
      String colorTransparent = "rgba(${p.r},${p.g},${p.b},0)";
      gradient.addColorStop(0, color);
      gradient.addColorStop(0.5, color);
      gradient.addColorStop(1, colorTransparent);
      context.fillStyle = gradient;   
    } else if (this.particleType == ParticleEffects_ParticleType.FIRE) {
      double lifePercentage = p.lifeTimeRemaining / this.particleLifeTime;
      double lifePercentageInverse = 1.0 - lifePercentage;   
      String color = 
          "rgba(${(260 * lifePercentage).toInt()}, ${(10 * lifePercentageInverse).toInt()}, ${(10 * lifePercentageInverse).toInt()}, ${lifePercentageInverse})";
      context.fillStyle = color.toJS;
    } else if (this.particleType == ParticleEffects_ParticleType.SODA) {
      double lifePercentage = p.lifeTimeRemaining / this.particleLifeTime;
      double lifePercentageInverse = 1.0 - lifePercentage;
      String color =
          "rgba(239, 204, 10, ${lifePercentageInverse})";
      context.fillStyle = color.toJS;
    } else if (this.particleType == ParticleEffects_ParticleType.CONFETTI) {
      String color = "rgba(${p.r},${p.g},${p.b},1.0)";
      context.fillStyle = color.toJS;
    } else if(this.particleType == ParticleEffects_ParticleType.BLOOD) {
      String color = "rgba(${80 + r.nextInt(120)},0,0,1.0)";
      context.fillStyle = color.toJS;
    }
  }

  collide(MovingSprite? other, var dynamic, int? direction) {
    if (!world.network().isCommander()) {
      return;
    }
    if (owner != null) {
      if (other != null && damage != null && other.takesDamage() &&
          other.networkId != owner!.networkId) {
        other.takeDamage(damage!, owner!, Mod.COFFEE);
        lifeTime = 0;
      } else if (direction != null && direction != 0 && damage != null) {
        world.explosionAt(
            location: centerPoint(),
            damage: damage!,
            radius: radius * 1.5,
            damagerDoer: owner);
        lifeTime = 0;
      }
    }
  }
}

class _Particle {
  late Vec2 location;
  late Vec2 speed;
  late int lifeTimeRemaining;
  late int r, g, b;
  late double radius;

  randomColor(Random ra) {
    r = ra.nextInt(255);
    g = ra.nextInt(255);
    b = ra.nextInt(255);
  }
  
  setToRandom(Random ra, double radius, Sprite? follow, Vec2? followOffset, Vec2 location,
      Vec2 velocityBase, int lifeTime, bool randomVelocity) {
    randomColor(ra);
    this.radius = (radius * ra.nextDouble());
    if (follow != null) {
      if (followOffset != null) {
        this.location = follow.centerPoint() + followOffset;
      } else {
        this.location = follow.centerPoint();
      }
    } else {
      this.location = new Vec2.copy(location);
    }
    double sum = velocityBase.sum();
    if (randomVelocity) {
      speed = new Vec2(velocityBase.x * ra.nextDouble(),
          velocityBase.y * ra.nextDouble());
      if (ra.nextBool()) {
        speed.x = -speed.x;
      }
      if (ra.nextBool()) {
        speed.y = -speed.y;
      }
    } else {
      speed = new Vec2(
          velocityBase.x + sum * ra.nextDouble() * 0.1 -
              sum * ra.nextDouble() * 0.1,
          velocityBase.y + sum * ra.nextDouble() * 0.1 -
              sum * ra.nextDouble() * 0.1);
    }
    lifeTimeRemaining = ra.nextInt(lifeTime);
  }
}