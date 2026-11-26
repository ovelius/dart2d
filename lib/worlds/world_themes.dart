/// The 8 playable ZooBlast world themes featured in the Mega Man-style
/// 3x3 world selector and procedural cartoon world generator.
enum WorldThemeId {
  villa,
  spooky,
  volcano,
  glacier,
  candy,
  lunar,
  city,
  jungle,
}

class WorldThemeSpec {
  final WorldThemeId id;
  final String key;
  final String name;
  final String subtitle;
  final double gravity;
  final String accentColor;
  final String badgeText;
  final List<String> skyColors;

  const WorldThemeSpec({
    required this.id,
    required this.key,
    required this.name,
    required this.subtitle,
    this.gravity = 300.0,
    required this.accentColor,
    this.badgeText = '',
    required this.skyColors,
  });

  bool get isLowGravity => gravity < 250.0;
}

const double DEFAULT_WORLD_GRAVITY = 300.0;
const double LUNAR_WORLD_GRAVITY = 145.0;

const List<WorldThemeSpec> WORLD_THEMES = [
  WorldThemeSpec(
    id: WorldThemeId.villa,
    key: 'villa',
    name: 'VILLA',
    subtitle: 'Crooked Garden',
    gravity: DEFAULT_WORLD_GRAVITY,
    accentColor: '#ffd23f',
    skyColors: ['#3eaef8', '#8adfff', '#fff9d6'],
  ),
  WorldThemeSpec(
    id: WorldThemeId.spooky,
    key: 'spooky',
    name: 'SPOOKY',
    subtitle: 'Haunted Keep',
    gravity: DEFAULT_WORLD_GRAVITY,
    accentColor: '#b96cff',
    skyColors: ['#241645', '#4c2b7a', '#7c4e96'],
  ),
  WorldThemeSpec(
    id: WorldThemeId.volcano,
    key: 'volcano',
    name: 'VOLCANO',
    subtitle: 'Lava Crater',
    gravity: DEFAULT_WORLD_GRAVITY,
    accentColor: '#ff6c36',
    skyColors: ['#3a1830', '#a6382c', '#ffb24c'],
  ),
  WorldThemeSpec(
    id: WorldThemeId.glacier,
    key: 'glacier',
    name: 'GLACIER',
    subtitle: 'Frosty Peaks',
    gravity: DEFAULT_WORLD_GRAVITY,
    accentColor: '#66ecff',
    skyColors: ['#3284d8', '#7ed8ff', '#e4fbff'],
  ),
  WorldThemeSpec(
    id: WorldThemeId.candy,
    key: 'candy',
    name: 'CANDY',
    subtitle: 'Sugar Rush',
    gravity: DEFAULT_WORLD_GRAVITY,
    accentColor: '#ff74b8',
    skyColors: ['#69c8ff', '#ffb8e0', '#fff4cc'],
  ),
  WorldThemeSpec(
    id: WorldThemeId.lunar,
    key: 'lunar',
    name: 'LUNAR',
    subtitle: 'Low Gravity!',
    gravity: LUNAR_WORLD_GRAVITY,
    accentColor: '#ffe054',
    badgeText: 'LOW G',
    skyColors: ['#0a1026', '#16224a', '#263870'],
  ),
  WorldThemeSpec(
    id: WorldThemeId.city,
    key: 'city',
    name: 'CITY',
    subtitle: 'Skyline Roofs',
    gravity: DEFAULT_WORLD_GRAVITY,
    accentColor: '#48b8ff',
    skyColors: ['#38a4f0', '#86d6ff', '#e8f7ff'],
  ),
  WorldThemeSpec(
    id: WorldThemeId.jungle,
    key: 'jungle',
    name: 'JUNGLE',
    subtitle: 'Ancient Ruins',
    gravity: DEFAULT_WORLD_GRAVITY,
    accentColor: '#a4e644',
    skyColors: ['#2e9c9a', '#6dd8a8', '#fff0b8'],
  ),
];

const String GENERATED_MAP_PREFIX = 'gen:';

String encodeGeneratedMapName(WorldThemeId themeId, int seed) {
  final WorldThemeSpec spec = worldThemeById(themeId);
  return '$GENERATED_MAP_PREFIX${spec.key}:$seed';
}

WorldThemeSpec worldThemeById(WorldThemeId id) {
  for (final WorldThemeSpec spec in WORLD_THEMES) {
    if (spec.id == id) return spec;
  }
  return WORLD_THEMES.first;
}

WorldThemeSpec? worldThemeByKey(String key) {
  for (final WorldThemeSpec spec in WORLD_THEMES) {
    if (spec.key == key) return spec;
  }
  return null;
}

class ParsedGeneratedMap {
  final WorldThemeSpec theme;
  final int seed;

  const ParsedGeneratedMap(this.theme, this.seed);
}

ParsedGeneratedMap? parseGeneratedMapName(String? mapName) {
  if (mapName == null || !mapName.startsWith(GENERATED_MAP_PREFIX)) {
    return null;
  }
  final List<String> parts = mapName.split(':');
  if (parts.length < 3) return null;
  final WorldThemeSpec? theme = worldThemeByKey(parts[1]);
  final int? seed = int.tryParse(parts[2]);
  if (theme == null || seed == null) return null;
  return ParsedGeneratedMap(theme, seed);
}

WorldThemeSpec? themeFromMapName(String? mapName) {
  return parseGeneratedMapName(mapName)?.theme;
}
