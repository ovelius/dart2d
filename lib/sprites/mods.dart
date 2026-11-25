import 'dart:math';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

final Logger log_ = new Logger('Mod');
final Random _modRandom = new Random();

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

typedef KillMessageBuilder = String Function(String killed, String killer);

Map<Mod, List<KillMessageBuilder>> _killedMessages = {
  Mod.ZOOKA: [
    (killed, killer) => "$killed got chomped by $killer's tiger rocket!",
    (killed, killer) => "$killed couldn't outrun $killer's Zooka tiger!",
    (killed, killer) => "$killed booped the snoot of $killer's Zooka!",
    (killed, killer) => "$killer's tiger rocket gave $killed a roaring blast!",
  ],
  Mod.DARTGUN: [
    (killed, killer) => "$killed was a bullseye for $killer's dart gun!",
    (killed, killer) => "$killer turned $killed into a dartboard!",
    (killed, killer) => "$killed got pinned by $killer's sharp dart!",
    (killed, killer) => "$killer scored triple-20 on $killed!",
  ],
  Mod.TV: [
    (killed, killer) => "$killed got a sugar rush from $killer's Jellybean Jet!",
    (killed, killer) => "$killed couldn't dodge $killer's bouncy jellybeans!",
    (killed, killer) => "$killer served $killed way too many jellybeans!",
    (killed, killer) => "$killed got beaned by $killer's Jellybean Jet!",
  ],
  Mod.BANANA: [
    (killed, killer) => "$killed went bananas over $killer's banana pancake!",
    (killed, killer) => "$killer served $killed an explosive pancake breakfast!",
    (killed, killer) => "$killed slipped right into $killer's banana stack!",
    (killed, killer) => "$killed got extra syrup from $killer's banana pancake!",
  ],
  Mod.COFFEE: [
    (killed, killer) => "$killed got roasted by $killer's scalding espresso!",
    (killed, killer) => "$killer poured $killed a piping hot cup of doom!",
    (killed, killer) => "$killed should've ordered decaf from $killer!",
    (killed, killer) => "$killed got double-shot by $killer's Coffee Burn!",
  ],
  Mod.LITTER: [
    (killed, killer) => "$killed got buried in $killer's cat litter box!",
    (killed, killer) => "$killer scooped $killed straight into the litter box!",
    (killed, killer) => "$killed had a catastrophic run-in with $killer's litter box!",
  ],
  Mod.BRICK: [
    (killed, killer) => "$killed ran straight into $killer's brick wall!",
    (killed, killer) => "$killer dropped a ton of bricks on $killed!",
    (killed, killer) => "$killed got bricked by $killer's masonry!",
  ],
  Mod.HYPER: [
    (killed, killer) => "$killed got zapped into neon dust by $killer!",
    (killed, killer) => "$killer fried $killed with neon-red lightning!",
    (killed, killer) => "$killed stared straight into $killer's Neon Blaster!",
    (killed, killer) => "$killed couldn't survive $killer's Neon Blaster meltdown!",
  ],
  Mod.SNAIL: [
    (killed, killer) => "$killed got outrun by $killer's turbo snails!",
    (killed, killer) => "$killed got shell-shocked by $killer's Snailgun!",
    (killed, killer) => "$killer's rocket snails left $killed in the slime!",
    (killed, killer) => "$killed was way too slow for $killer's snails!",
  ],
  Mod.SHOTGUN: [
    (killed, killer) => "$killed got blasted by $killer's monkey shotgun!",
    (killed, killer) => "$killer gave $killed a whole bucket of pellets!",
    (killed, killer) => "$killed walked right into $killer's shotgun scatter!",
  ],
  Mod.UNKNOWN: [
    (killed, killer) => "$killed went poof thanks to $killer!",
    (killed, killer) => "$killed met a cartoon end courtesy of $killer!",
  ],
};

Map<Mod, String Function(String player)> _selfKillMessages = {
  Mod.ZOOKA: (p) => "$p got chomped by their own tiger rocket!",
  Mod.BANANA: (p) => "$p ate too much of their own banana pancake!",
  Mod.COFFEE: (p) => "$p spilled scalding coffee on themselves!",
  Mod.LITTER: (p) => "$p jumped into their own cat litter box!",
  Mod.HYPER: (p) => "$p got toasted by their own Neon Blaster!",
  Mod.TV: (p) => "$p bounced into their own jellybeans!",
  Mod.SNAIL: (p) => "$p got caught by their own snails!",
};

final List<String Function(String player)> _genericSelfKillMessages = [
  (p) => "$p outplayed themselves!",
  (p) => "$p went kaboom all by themselves!",
  (p) => "$p forgot which end of the gun points out!",
];

String killedMessage(String killed, String killer, Mod mod) {
  List<KillMessageBuilder>? options = _killedMessages[mod];
  if (options != null && options.isNotEmpty) {
    return options[_modRandom.nextInt(options.length)](killed, killer);
  }
  return "$killed was knocked out by $killer!";
}

String selfKillMessage(String player, Mod mod) {
  String Function(String)? specific = _selfKillMessages[mod];
  if (specific != null) {
    return specific(player);
  }
  return _genericSelfKillMessages[_modRandom.nextInt(_genericSelfKillMessages.length)](player);
}