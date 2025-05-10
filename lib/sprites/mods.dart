import 'package:logging/logging.dart' show Logger, Level, LogRecord;

final Logger log_ = new Logger('Mod');

enum Mod {
  ZOOKA,
  DARTGUN,
  TV,
  BANANA,
  HYPER,
  COFFEE,
  LITTER,
  SNAIL,
  BRICK,
  SHOTGUN,
  UNKNOWN,
}

Map<Mod, dynamic> _killedMessages = {
  Mod.ZOOKA: (String killed, String killer) => "$killed didn't see ${killer}'s Zooka shot",
  Mod.DARTGUN: (String killed, String killer) => "$killed got darts in the face from ${killer}'s dart gun",
  Mod.TV: (String killed, String killer) => "$killed watched too much of ${killer}'s rubber ball commercial",
  Mod.BANANA: (String killed, String killer) => "$killed went bananas from ${killer}'s banana pankcake",
  Mod.COFFEE: (String killed, String killer) => "$killed got burned by ${killer}'s coffee",
  Mod.LITTER: (String killed, String killer) => "$killed took a dive in ${killer}'s cat litter box",
  Mod.BRICK: (String killed, String killer) => "$killed got hit by a ${killer}'s bricks",
  Mod.HYPER: (String killed, String killer) => "$killed neon neon neon ${killer}'s blaster bream",
  Mod.SNAIL: (String killed, String killer) => "$killed was too slow for ${killer}'s snails",
  Mod.SHOTGUN: (String killed, String killer) => "$killed went on a date with ${killer}'s Old Betsy",
  Mod.UNKNOWN: (String killed, String killer) => "$killed died"
};

String killedMessage(String killed, String killer, Mod mod) {
  if (_killedMessages.containsKey(mod)) {
    return _killedMessages[mod](killed, killer);
  }
  return "$killed was killed by $killer";
}