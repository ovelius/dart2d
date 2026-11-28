import 'package:dart2d/weapons/weapon_state.dart';

class Weapon {
  // Static setup.
  String name;
  int shotsPerClip = 5;
  double reloadTime = 5.0;
  double fireDelay = 0.5;
  dynamic fire;
  // Instance state.
  double untilReload = 0.0;
  double untilNextFire = 0.0;
  int shotsLeft = 0;

  int iconIndex = 0;
  bool hasLaserSight = false;
  bool isMysteryWeapon = false;
  double mysteryWeight = 1.0;
  bool unlocked = true;

  Weapon(this.name, this.iconIndex, this.shotsPerClip, this.reloadTime,
      this.fireDelay, this.fire,
      {this.hasLaserSight = false,
      this.isMysteryWeapon = false,
      this.mysteryWeight = 1.0}) {
    this.shotsLeft = shotsPerClip;
    this.unlocked = !this.isMysteryWeapon;
  }

  void fireButton(WeaponState weaponState) {
    if (shotsLeft > 0) {
      if (untilNextFire <= 0) {
        untilNextFire = fireDelay;
        shotsLeft--;
        fire(weaponState);
        if (shotsLeft <= 0) {
          if (isMysteryWeapon && !weaponState.isSandboxMode) {
            unlocked = false;
            untilReload = 0.0;
            weaponState.onMysteryWeaponDepleted(this);
          } else {
            untilReload = reloadTime;
          }
        }
      }
    }
  }

  void think(double duration, {bool allowAutoReload = true}) {
    untilNextFire -= duration;
    untilReload -= duration;
    if (shotsLeft <= 0 && untilReload < 0) {
      if (!isMysteryWeapon || allowAutoReload) {
        shotsLeft = shotsPerClip;
        untilNextFire = 0.10;
      }
    }
  }
  
  bool reloading() {
    return untilReload > 0; 
  }
  
  int reloadPercent() {
    return (untilReload * 100 ~/ reloadTime);
  }

  String toString() => "Weapon $name";
}