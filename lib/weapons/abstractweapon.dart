abstract class AbstractWeapon {
  // Static setup.
  int shotsPerClip = 5;
  double reloadTime = 5.0;
  double fireDelay = 0.5;
  // Instance state.
  double untilReload = 0.0;
  double untilNextFire = 0.0;
  int shotsLeft;
  
  AbstractWeapon(this.shotsPerClip, this.reloadTime, this.fireDelay) {
    shotsLeft = shotsPerClip;
  }
  
  void fireButton(double duration) {
    if (shotsLeft > 0) {
      untilNextFire -= duration;
      if (untilNextFire <= 0) {
        untilNextFire += fireDelay;
        shotsLeft--;
        fire();
        if (shotsLeft <= 0) {
          untilReload += reloadTime;
        }
      }
    } else {
      untilReload -= duration;
      if (untilReload < 0) {
        shotsLeft = shotsPerClip;
        untilNextFire = 0.0;
      }
    }
  }
  
  void fire();
}