
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
      _Particle p = _Particle.acquire();
      p.setToRandom(r, radius, follow, followOffset, position, velocityBase, lifeTime,
          RANDOM_VELOCITY_PARTICLES.contains(particleType),
          isRocketTrail: particleType == ParticleEffects_ParticleType.COLORFUL,
          isCoffee: particleType == ParticleEffects_ParticleType.FIRE,
          initialSpawn: true);
      particles.add(p);
    }
    this.radius = radius;
    this.particleLifeTime = lifeTime;
    this.world = world;
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
       _Particle p = _Particle.acquire();
       p.setToRandom(r, radius, follow, followOffset, position, velocity, particleLifeTime,
           RANDOM_VELOCITY_PARTICLES.contains(particleType),
           isRocketTrail: particleType == ParticleEffects_ParticleType.COLORFUL,
           isCoffee: particleType == ParticleEffects_ParticleType.FIRE,
           initialSpawn: true);
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
    bool isRocketTrail = this.particleType == ParticleEffects_ParticleType.COLORFUL;
    double drag = max(0.0, 1.0 - duration * 3.0);
    for(var i = 0; i < particles.length; i++) {
      _Particle p = particles[i];
      p.location.x += p.speed.x * duration;
      p.location.y += p.speed.y * duration;
      if(p.lifeTimeRemaining < 0 || (!isRocketTrail && p.radius < 0)) {
        continue;
      }
      if (isRocketTrail) {
        // Rocket exhaust slows down in air and drifts slightly upward as warm smoke.
        p.speed.x *= drag;
        p.speed.y *= drag;
        p.location.y -= 16.0 * duration;
      } else if (g != null) {
        if (this.particleType != ParticleEffects_ParticleType.FIRE) {
          p.location += g;
        }
        if (RANDOM_VELOCITY_PARTICLES.contains(particleType)) {
          p.speed += g.multiply(6.0);
        }
      }
      p.lifeTimeRemaining--;
      if (!isRocketTrail) {
        p.radius -= shrinkPerStep;
      }
    }
    super.frame(duration, frames, Vec2.ZERO);
  }
  void release() {
    for (_Particle p in particles) {
      _Particle.release(p);
    }
    particles.clear();
  }

  draw(CanvasRenderingContext2D context, bool debug) {
    context.save();
    int dead = 0;
    Random r = new Random();

    if (particleType == ParticleEffects_ParticleType.COLORFUL) {
      // Realistic rocket exhaust trail (shared by Zooka and Snailgun):
      // young particles glow hot flame at the nozzle, then expand into soft billowing smoke.
      dead = _drawRocketTrail(context, r);
      if (dead == particles.length) {
        this.remove = true;
      }
      context.restore();
      return;
    }

    if (particleType == ParticleEffects_ParticleType.FIRE) {
      // Scalding coffee spray (Coffee Burn): rich dark-roast espresso stream with
      // caramel crema sheen that cools into soft rising steam wisps.
      dead = _drawCoffeeStream(context, r);
      if (dead == particles.length) {
        this.remove = true;
      }
      context.restore();
      return;
    }

    if (particleType != ParticleEffects_ParticleType.SODA
     && particleType != ParticleEffects_ParticleType.BLOOD) {
      context.globalCompositeOperation = "lighter";
    }

    bool useSimpleRect = (particleType == ParticleEffects_ParticleType.FIRE || 
                          particleType == ParticleEffects_ParticleType.SODA ||
                          particleType == ParticleEffects_ParticleType.BLOOD ||
                          particleType == ParticleEffects_ParticleType.CONFETTI);

    if (useSimpleRect) {
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
        setFillStyle(context, p, r);
        context.fillRect(p.location.x - p.radius, p.location.y - p.radius, p.radius * 2, p.radius * 2);
      }
    } else {
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
    }
    
    if (dead == particles.length) {
      this.remove = true;
    }
    context.restore();
  }

  int _drawRocketTrail(CanvasRenderingContext2D context, Random r) {
    int dead = 0;
    double maxLife = max(1, this.particleLifeTime).toDouble();

    // First handle respawns and draw billowing smoke puffs (normal alpha blend).
    context.globalCompositeOperation = "source-over";
    for (int i = 0; i < particles.length; i++) {
      _Particle p = particles[i];
      if (p.lifeTimeRemaining < 0) {
        if (follow != null && !follow!.remove) {
          p.setToRandom(r, radius, follow, followOffset, position, velocity, this.particleLifeTime,
              false, isRocketTrail: true, initialSpawn: false);
        } else {
          dead++;
          continue;
        }
      }
      double lifeFrac = (p.lifeTimeRemaining / maxLife).clamp(0.0, 1.0);
      if (lifeFrac > 0.85) {
        continue;
      }
      double ageFrac = 1.0 - lifeFrac;
      double smokeRadius = max(1.5, p.radius * (0.65 + 1.35 * ageFrac));
      double smokeAlpha = (lifeFrac < 0.7 ? lifeFrac / 0.7 : (0.85 - lifeFrac) / 0.15) * 0.42;
      if (smokeAlpha <= 0.01) {
        continue;
      }
      int shade = (95 + (115 * ageFrac)).toInt().clamp(90, 215);
      CanvasGradient grad = context.createRadialGradient(
          p.location.x, p.location.y, 0, p.location.x, p.location.y, smokeRadius);
      grad.addColorStop(0.0, "rgba($shade, ${shade - 3}, ${shade - 6}, ${smokeAlpha.toStringAsFixed(2)})");
      grad.addColorStop(0.55, "rgba($shade, $shade, $shade, ${(smokeAlpha * 0.6).toStringAsFixed(2)})");
      grad.addColorStop(1.0, "rgba($shade, $shade, $shade, 0)");
      context.fillStyle = grad;
      context.beginPath();
      context.arc(p.location.x, p.location.y, smokeRadius, 0, pi * 2.0);
      context.fill();
    }

    // Second pass: hot glowing exhaust flame right behind the rocket nozzle.
    context.globalCompositeOperation = "lighter";
    for (int i = 0; i < particles.length; i++) {
      _Particle p = particles[i];
      if (p.lifeTimeRemaining < 0) {
        continue;
      }
      double lifeFrac = (p.lifeTimeRemaining / maxLife).clamp(0.0, 1.0);
      if (lifeFrac <= 0.68) {
        continue;
      }
      double flameT = ((lifeFrac - 0.68) / 0.32).clamp(0.0, 1.0); // 1.0 = hottest at nozzle
      double flameRadius = max(1.5, p.radius * (0.55 + 0.55 * flameT));
      int gVal = (90 + 165 * flameT).toInt().clamp(0, 255);
      int bVal = (210 * flameT * flameT).toInt().clamp(0, 255);
      double flameAlpha = (0.35 + 0.65 * flameT).clamp(0.0, 1.0);
      CanvasGradient grad = context.createRadialGradient(
          p.location.x, p.location.y, 0, p.location.x, p.location.y, flameRadius);
      grad.addColorStop(0.0, "rgba(255, $gVal, $bVal, ${flameAlpha.toStringAsFixed(2)})");
      grad.addColorStop(0.5, "rgba(255, ${(gVal * 0.65).toInt()}, 15, ${(flameAlpha * 0.6).toStringAsFixed(2)})");
      grad.addColorStop(1.0, "rgba(220, 40, 0, 0)");
      context.fillStyle = grad;
      context.beginPath();
      context.arc(p.location.x, p.location.y, flameRadius, 0, pi * 2.0);
      context.fill();
    }

    return dead;
  }

  int _drawCoffeeStream(CanvasRenderingContext2D context, Random r) {
    int dead = 0;
    double maxLife = max(1, this.particleLifeTime).toDouble();
    context.globalCompositeOperation = "source-over";

    // Pass 1: Soft rising warm steam wisps around the coffee spray.
    for (int i = 0; i < particles.length; i++) {
      _Particle p = particles[i];
      if (p.lifeTimeRemaining < 0 || p.radius < 0) {
        if (follow != null && !follow!.remove) {
          p.setToRandom(r, radius, follow, followOffset, position, velocity,
              this.particleLifeTime, false, isCoffee: true);
        } else {
          dead++;
          continue;
        }
      }
      double lifeFrac = (p.lifeTimeRemaining / maxLife).clamp(0.0, 1.0);
      double ageFrac = 1.0 - lifeFrac;
      double steamVisibility =
          (ageFrac < 0.2 ? ageFrac / 0.2 : 1.0) * (lifeFrac < 0.35 ? lifeFrac / 0.35 : 1.0);
      if (steamVisibility <= 0.02) {
        continue;
      }
      double steamRise = (4.0 + 14.0 * ageFrac) * (0.75 + 0.5 * (p.g / 255.0));
      double steamRadius = (p.radius * 0.95).clamp(4.0, 24.0);
      double steamAlpha = 0.26 * steamVisibility;
      double sx = p.location.x;
      double sy = p.location.y - steamRise;
      CanvasGradient grad =
          context.createRadialGradient(sx, sy, 0, sx, sy, steamRadius);
      grad.addColorStop(0.0, "rgba(242, 232, 218, ${steamAlpha.toStringAsFixed(2)})");
      grad.addColorStop(0.6, "rgba(225, 212, 196, ${(steamAlpha * 0.5).toStringAsFixed(2)})");
      grad.addColorStop(1.0, "rgba(220, 208, 195, 0)");
      context.fillStyle = grad;
      context.beginPath();
      context.arc(sx, sy, steamRadius, 0, pi * 2.0);
      context.fill();
    }

    // Pass 2: Rich dark-roast espresso droplets & caramel crema sheen,
    // fading smoothly out over each droplet's exact original lifetime.
    for (int i = 0; i < particles.length; i++) {
      _Particle p = particles[i];
      if (p.lifeTimeRemaining < 0 || p.radius < 0) {
        continue;
      }
      double lifeFrac = (p.lifeTimeRemaining / maxLife).clamp(0.0, 1.0);
      double dropR = (p.radius * 0.62).clamp(2.5, 13.5);
      double alpha = (lifeFrac < 0.35 ? (lifeFrac / 0.35) * 0.9 : 0.9).clamp(0.0, 0.92);

      // Blend from rich crema-mocha to deep espresso brown per droplet (using p.r as stable seed).
      double roastMix = p.r / 255.0;
      int cr = (48 + 52 * roastMix).toInt();
      int cg = (22 + 30 * roastMix).toInt();
      int cb = (8 + 12 * roastMix).toInt();

      // Liquid splash streak behind moving droplets.
      double speedSq = p.speed.x * p.speed.x + p.speed.y * p.speed.y;
      if (speedSq > 400.0) {
        context.strokeStyle = "rgba($cr, $cg, $cb, ${(alpha * 0.68).toStringAsFixed(2)})".toJS;
        context.lineWidth = dropR * 1.25;
        context.lineCap = "round";
        context.beginPath();
        context.moveTo(p.location.x, p.location.y);
        context.lineTo(p.location.x - p.speed.x * 0.022, p.location.y - p.speed.y * 0.022);
        context.stroke();
      }

      // Main dark-roast espresso droplet.
      context.fillStyle = "rgba($cr, $cg, $cb, ${alpha.toStringAsFixed(2)})".toJS;
      context.beginPath();
      context.arc(p.location.x, p.location.y, dropR, 0, pi * 2.0);
      context.fill();

      // Glossy caramel crema highlight.
      if (dropR > 3.2) {
        context.fillStyle = "rgba(210, 152, 88, ${(alpha * 0.6).toStringAsFixed(2)})".toJS;
        context.beginPath();
        context.arc(p.location.x - dropR * 0.28, p.location.y - dropR * 0.28, dropR * 0.34, 0, pi * 2.0);
        context.fill();
      }
    }

    return dead;
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
      if (other != null && damage != null && other.takesDamage(Mod.COFFEE) &&
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
  static final List<_Particle> _pool = [];
  
  static _Particle acquire() {
    if (_pool.isEmpty) return _Particle();
    return _pool.removeLast();
  }
  
  static void release(_Particle p) {
    _pool.add(p);
  }

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
      Vec2 velocityBase, int lifeTime, bool randomVelocity,
      {bool isRocketTrail = false, bool isCoffee = false, bool initialSpawn = false}) {
    randomColor(ra);
    if (isRocketTrail) {
      this.radius = radius * (0.45 + 0.55 * ra.nextDouble());
    } else if (isCoffee) {
      this.radius = radius * (0.55 + 0.45 * ra.nextDouble());
    } else {
      this.radius = radius * ra.nextDouble();
    }
    if (follow != null) {
      if (followOffset != null) {
        this.location = follow.centerPoint() + followOffset;
      } else {
        this.location = follow.centerPoint();
      }
      if (isRocketTrail) {
        this.location.x += (ra.nextDouble() - 0.5) * 4.0;
        this.location.y += (ra.nextDouble() - 0.5) * 4.0;
      }
    } else {
      this.location = new Vec2.copy(location);
    }
    double sum = velocityBase.sum();
    if (isRocketTrail) {
      // Gentle billowing exhaust spread trailing behind the projectile.
      double spread = max(18.0, sum * 0.25);
      speed = new Vec2(
          -velocityBase.x * 0.15 + (ra.nextDouble() - 0.5) * spread,
          -velocityBase.y * 0.15 + (ra.nextDouble() - 0.5) * spread);
      if (initialSpawn) {
        // Stagger initial pool lifetimes so emission is continuous rather than clumped.
        lifeTimeRemaining = ra.nextInt(max(1, lifeTime));
      } else {
        // Freshly emitted trail puffs always start hot at the nozzle.
        lifeTimeRemaining = max(1, (lifeTime * (0.85 + 0.15 * ra.nextDouble())).toInt());
      }
      return;
    }
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
    lifeTimeRemaining = isCoffee
        ? max(1, (lifeTime * (0.7 + 0.3 * ra.nextDouble())).round())
        : ra.nextInt(max(1, lifeTime));
  }
}