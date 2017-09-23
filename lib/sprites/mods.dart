import 'package:logging/logging.dart' show Logger, Level, LogRecord;

final Logger log_ = new Logger('Mod');

enum Mod {
  ZOOKA,
  DARTGUN,
  TV,
  BANANA,
  COFFEE,
  LITTER,
  UNKNOWN,
}

Map<Mod, dynamic> _killedMessages = {
  Mod.ZOOKA: (String killed, String killer) => "$killed didn't see ${killer}'s Zooka shot",
  Mod.DARTGUN: (String killed, String killer) => "$killed got darts in the face from ${killer}'s dart gun",
  Mod.TV: (String killed, String killer) => "$killed watched too much of ${killer}'s rubber ball commercial",
  Mod.BANANA: (String killed, String killer) => "$killed went bananas from ${killer}'s banana pankcake",
  Mod.COFFEE: (String killed, String killer) => "$killed got burned by ${killer}'s coffee",
  Mod.LITTER: (String killed, String killer) => "$killed took a dive in ${killer}'s cat litter box",
};

String killedMessage(String killed, String killer, Mod mod) {
  if (_killedMessages.containsKey(mod)) {
    return _killedMessages[mod](killed, killer);
  }
  // TODO: Bring this back!
  // log_.warning("Missing custom message for ${mod}!");
  return "$killed was killed by $killer";
}