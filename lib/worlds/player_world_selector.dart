import 'dart:js_interop';
import 'dart:math';
import 'package:clock/clock.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart' show Logger;
import 'package:web/web.dart';

import '../net/connection.dart';
import '../net/helpers.dart';
import '../net/network.dart';
import 'world_data.dart';
import 'world_generator.dart';
import 'world_themes.dart';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/res/imageindex.dart';

@Singleton(scope: 'world')
class PlayerWorldSelector {
  static final Logger _log = Logger('PlayerWorldSelector');
  static const double MAP_TIE_BREAK_WINDOW_SECONDS = 1.0;
  static const double _TIE_BREAK_IN_FLIGHT_GRACE_SECONDS = 2.5;
  static final double UPDATE_SELECTION_TO_NETWORK_TIME = 0.3;
  static final List<String> PLAYER_SPRITES = [
    "sheep98.png",
    "ele96.png",
    "donkey98.png",
    "goat93.png",
    "cock77.png",
    "lion88.png",
    "dra98.png",
    "turtle96.png"
  ];
  static final List<int> PLAYER_SPRITE_SIZES = [120, 120, 120, 116, 100, 116, 120, 120];

  static final List<String> AVAILABLE_MAPS =
      WORLD_THEMES.map((t) => t.key).toList();

  /// Clockwise 3x3 Mega Man grid positions (col, row) for the 8 world themes
  /// surrounding the player sprite in the center cell (1, 1):
  ///   [0: Villa   ] [1: Spooky] [2: Volcano]
  ///   [7: Jungle  ] [ PLAYER  ] [3: Glacier]
  ///   [6: Toy Land] [5: Lunar ] [4: Candy  ]
  static const List<Point<int>> _GRID_COORDS = [
    Point(0, 0),
    Point(1, 0),
    Point(2, 0),
    Point(2, 1),
    Point(2, 2),
    Point(1, 2),
    Point(0, 2),
    Point(0, 1),
  ];

  static int playerSpriteWidth(String name) {
    for (int i = 0; i < PLAYER_SPRITES.length; i++) {
      if (name == PLAYER_SPRITES[i]) {
        return PLAYER_SPRITE_SIZES[i];
      }
    }
    throw "No player sprite named $name";
  }

  late CanvasRenderingContext2D _context;
  late LocalStorage _localStorage;
  late KeyState _keyState;
  late MobileControls _mobileControls;
  late ImageIndex _imageIndex;
  late Network _network;
  late GaReporter _gaReporter;
  late String _botName;
  late PacketListenerBindings _packetListenerBindings;
  late int _width;
  late int _height;

  int _selectedPlayerSprite = new Random().nextInt(PLAYER_SPRITES.length);
  int _animateX = 0;
  double _frameTime = 0.00;
  double _animTime = 0.0;

  int _selectedMap = new Random().nextInt(WORLD_THEMES.length);
  int get selectedMapIndex => _selectedMap;

  String? _selectedWorldName = null;
  String? get selectedWorldName => _selectedWorldName;

  String? _selectedWorldOwnerId = null;
  bool _selectedLocally = false;
  DateTime? _localSelectionWallTime = null;
  double _localSelectionTickSeconds = 0.0;
  DateTime? _remoteSelectionWallTime = null;
  double _remoteSelectionTickSeconds = 0.0;
  void Function(String winnerId, String winnerMapName)?
      _onRollbackMapSelection = null;

  String? _customMessage = null;

  double _nextSendToNetwork = 0.0;
  bool clearBackground = true;
  double _fadeInProgress = 0.0;
  bool _lastFrameWasPlayerSelect = false;
  bool _hasRenderedOnce = false;

  List<Rectangle<double>>? _mapTileRects = null;
  List<Rectangle<double>>? _playerCardRects = null;
  Rectangle<double>? _confirmButtonRect = null;
  List<List<String>> _otherPlayersSelections =
      List.generate(WORLD_THEMES.length, (_) => <String>[]);

  PlayerWorldSelector(
      this._packetListenerBindings,
      this._network,
      this._mobileControls,
      this._imageIndex,
      this._gaReporter,
      ConfigParams _configParams,
      LocalStorage storage,
      KeyState localKeyState,
      WorldCanvas canvasElement) {
    _context = canvasElement.context2D;
    _width = canvasElement.width;
    _height = canvasElement.height;
    _localStorage = storage;
    _keyState = localKeyState;
    _keyState.registerListener(KeyCodeDart.LEFT, () {
      _animateX = 0;
      if (!playerSelected()) {
        _selectedPlayerSprite =
            (_selectedPlayerSprite - 1 + PLAYER_SPRITES.length) %
                PLAYER_SPRITES.length;
      } else {
        _moveGridSelection(-1, 0);
      }
    });
    _keyState.registerListener(KeyCodeDart.RIGHT, () {
      _animateX = 0;
      if (!playerSelected()) {
        _selectedPlayerSprite =
            (_selectedPlayerSprite + 1) % PLAYER_SPRITES.length;
      } else {
        _moveGridSelection(1, 0);
      }
    });
    _keyState.registerListener(KeyCodeDart.UP, () {
      _animateX = 0;
      if (!playerSelected()) {
        _selectedPlayerSprite =
            (_selectedPlayerSprite - 4 + PLAYER_SPRITES.length) %
                PLAYER_SPRITES.length;
      } else {
        _moveGridSelection(0, -1);
      }
    });
    _keyState.registerListener(KeyCodeDart.DOWN, () {
      _animateX = 0;
      if (!playerSelected()) {
        _selectedPlayerSprite =
            (_selectedPlayerSprite + 4) % PLAYER_SPRITES.length;
      } else {
        _moveGridSelection(0, 1);
      }
    });
    _keyState.registerListener(KeyCodeDart.SPACE, maybeSelectPlayerOrMap);
    _keyState.registerListener(KeyCodeDart.ENTER, maybeSelectPlayerOrMap);
    _keyState.registerListener(KeyCodeDart.CTRL, maybeSelectPlayerOrMap);
    _mobileControls.listenForTouch((int x, int y) {
      // Ignore lobby selector touches once loading has completed or we are in-game!
      if (_network.safeLoaderCompleted()) {
        return;
      }
      final String? selfId = _network.getPeer().getId();
      if (selfId != null && _network.gameState.isInGame(selfId)) {
        return;
      }

      if (!playerSelected()) {
        // Ensure card layout exists even if a touch arrives on the very first frame.
        if (_playerCardRects == null) {
          _partitionSprites();
        }
        if (_confirmButtonRect != null &&
            _rectContains(_confirmButtonRect!, x, y)) {
          maybeSelectPlayerOrMap();
          return;
        }
        if (_playerCardRects != null) {
          for (int i = 0; i < _playerCardRects!.length; i++) {
            if (_rectContains(_playerCardRects![i], x, y)) {
              if (_selectedPlayerSprite == i) {
                maybeSelectPlayerOrMap();
              } else {
                _selectedPlayerSprite = i;
                _animateX = 0;
                _customMessage = "Tap again or press PLAY!";
              }
              return;
            }
          }
        }
      } else if (_selectedWorldName == null &&
          _network.getServerConnection() == null &&
          !_network.gameState.hasCommander()) {
        if (_confirmButtonRect != null &&
            _rectContains(_confirmButtonRect!, x, y)) {
          maybeSelectPlayerOrMap();
          return;
        }
        if (_mapTileRects != null) {
          for (int i = 0; i < _mapTileRects!.length; i++) {
            if (_rectContains(_mapTileRects![i], x, y)) {
              if (_selectedMap == i) {
                maybeSelectPlayerOrMap();
              } else {
                _selectedMap = i;
                _customMessage = "Tap again or press DROP IN!";
              }
              return;
            }
          }
        }
      }
    });
    _packetListenerBindings.bindHandler(StateUpdate_Update.otherPlayerWorldSelect,
        (ConnectionWrapper connection, StateUpdate update) {
      String playerName = update.otherPlayerWorldSelect.name;
      int selectedIndex = update.otherPlayerWorldSelect.worldSelectedIndex;
      for (List existingSelection in _otherPlayersSelections) {
        existingSelection.remove(playerName);
      }
      if (selectedIndex >= 0 && selectedIndex < _otherPlayersSelections.length) {
        _otherPlayersSelections[selectedIndex].add(playerName);
      }
    });
    _packetListenerBindings.bindHandler(StateUpdate_Update.commanderMapSelected,
        (ConnectionWrapper connection, StateUpdate update) {
      _handleRemoteCommanderMapSelected(connection, update.commanderMapSelected);
    });
    // Always allow to reselect the player image again.
    _localStorage.remove('playerSprite');

    // Bot enabled, let's set things up right away.
    _botName = _configParams.getString(ConfigParam.BOT_ENABLED);
    if (_botName.isNotEmpty) {
      _localStorage['playerName'] = _botName;
      _localStorage['playerSprite'] = PLAYER_SPRITES[_selectedPlayerSprite];
    }
  }

  /// Moves the Mega Man 3x3 selection cursor by (dx, dy), wrapping cleanly and
  /// hopping across the center player square (1, 1).
  void _moveGridSelection(int dx, int dy) {
    final Point<int> cur = _GRID_COORDS[_selectedMap % _GRID_COORDS.length];
    int col = (cur.x + dx + 3) % 3;
    int row = (cur.y + dy + 3) % 3;
    if (col == 1 && row == 1) {
      col = (col + dx + 3) % 3;
      row = (row + dy + 3) % 3;
    }
    for (int i = 0; i < _GRID_COORDS.length; i++) {
      if (_GRID_COORDS[i].x == col && _GRID_COORDS[i].y == row) {
        _selectedMap = i;
        return;
      }
    }
  }

  bool _rectContains(Rectangle<double> r, int x, int y) {
    return x >= r.left && x <= r.right && y >= r.top && y <= r.bottom;
  }

  bool _onPoint(Point<int> p, int x, int y, double scaledWidth) {
    return _onPointRect(p, x, y, scaledWidth, scaledWidth);
  }

  bool _onPointRect(
      Point<int> p, int x, int y, double scaledWidth, double scaledHeight) {
    if (x >= p.x && x <= p.x + scaledWidth) {
      if (y >= p.y && y <= p.y + scaledHeight) {
        return true;
      }
    }
    return false;
  }

  double _effectiveLocalSelectionElapsedSeconds() {
    if (_localSelectionWallTime == null) {
      return double.infinity;
    }
    final double wallSeconds =
        clock.now().difference(_localSelectionWallTime!).inMicroseconds / 1e6;
    return max(_localSelectionTickSeconds, wallSeconds);
  }

  double _effectiveRemoteSelectionElapsedSeconds() {
    if (_remoteSelectionWallTime == null) {
      return double.infinity;
    }
    final double wallSeconds =
        clock.now().difference(_remoteSelectionWallTime!).inMicroseconds / 1e6;
    return max(_remoteSelectionTickSeconds, wallSeconds);
  }

  bool _isWithinLocalTieBreakWindow() =>
      _selectedLocally &&
      _effectiveLocalSelectionElapsedSeconds() <= MAP_TIE_BREAK_WINDOW_SECONDS;

  bool _isWithinLocalInFlightGrace() =>
      _selectedLocally &&
      _effectiveLocalSelectionElapsedSeconds() <=
          _TIE_BREAK_IN_FLIGHT_GRACE_SECONDS;

  bool _isWithinRemoteTieBreakWindow() =>
      !_selectedLocally &&
      _selectedWorldOwnerId != null &&
      _effectiveRemoteSelectionElapsedSeconds() <= MAP_TIE_BREAK_WINDOW_SECONDS;

  bool _isWithinRemoteInFlightGrace() =>
      !_selectedLocally &&
      _selectedWorldOwnerId != null &&
      _effectiveRemoteSelectionElapsedSeconds() <=
          _TIE_BREAK_IN_FLIGHT_GRACE_SECONDS;

  void _resendLocalWinningMapTo(ConnectionWrapper connection) {
    final String? mapName = _selectedWorldName;
    if (mapName == null || mapName.isEmpty) {
      return;
    }
    _network.gameState.gameStateProto.mapName = mapName;
    connection.sendSingleUpdate(StateUpdate()
      ..attachSingleTonUniqueDataReceipt()
      ..commanderMapSelected = mapName);
    connection.sendSingleUpdate(StateUpdate()
      ..gameState = _network.gameState.gameStateProto);
  }

  void _applyRemoteWinningSelection(String winnerId, String winnerMapName) {
    _selectedLocally = false;
    _selectedWorldOwnerId = winnerId;
    _localSelectionWallTime = null;
    _localSelectionTickSeconds = 0.0;
    _remoteSelectionWallTime = clock.now();
    _remoteSelectionTickSeconds = 0.0;
    _onRollbackMapSelection?.call(winnerId, winnerMapName);
    if (winnerMapName.isNotEmpty) {
      _loadSelectedWorldMap(winnerMapName);
    }
  }

  void _handleRemoteCommanderMapSelected(
      ConnectionWrapper connection, String remoteMap) {
    if (remoteMap.isEmpty) {
      return;
    }
    final String remoteId = connection.id;
    final String localId = _network.getPeer().getId() ?? '';

    if (_selectedWorldName == null) {
      _selectedLocally = false;
      _selectedWorldOwnerId = remoteId;
      _remoteSelectionWallTime = clock.now();
      _remoteSelectionTickSeconds = 0.0;
      if (_network.gameState.gameStateProto.actingCommanderId.isEmpty) {
        _network.gameState.gameStateProto.actingCommanderId = remoteId;
      }
      _loadSelectedWorldMap(remoteMap);
      return;
    }

    if (_selectedWorldName == remoteMap && _selectedWorldOwnerId == remoteId) {
      return;
    }

    if (_selectedLocally) {
      if (!_isWithinLocalTieBreakWindow()) {
        _log.info(
            "Ignoring remote map '$remoteMap' from '$remoteId' (> ${MAP_TIE_BREAK_WINDOW_SECONDS}s after local map selection '$_selectedWorldName').");
        return;
      }
      if (remoteId.compareTo(localId) > 0) {
        _log.info(
            "Map tie-break won by higher natural ID '$remoteId' over '$localId'; rolling back '$_selectedWorldName' -> '$remoteMap'.");
        _applyRemoteWinningSelection(remoteId, remoteMap);
      } else {
        _log.info(
            "Map tie-break won by local higher natural ID '$localId' over '$remoteId'; keeping '$_selectedWorldName'.");
        _resendLocalWinningMapTo(connection);
      }
      return;
    }

    // Bystander peer: if two other peers selected maps within 1s, converge on
    // the higher natural ID peer's map.
    final String? currentOwner = _selectedWorldOwnerId;
    if (_isWithinRemoteTieBreakWindow() &&
        currentOwner != null &&
        remoteId.compareTo(currentOwner) > 0) {
      _log.info(
          "Bystander switching simultaneous map selection from '$currentOwner' to higher ID '$remoteId' ('$remoteMap').");
      _applyRemoteWinningSelection(remoteId, remoteMap);
    } else if (_selectedWorldName != remoteMap && currentOwner == remoteId) {
      _loadSelectedWorldMap(remoteMap);
    }
  }

  void _loadSelectedWorldMap(String mapName) {
    _selectedWorldName = mapName;
    if (mapName.isNotEmpty) {
      _network.gameState.gameStateProto.mapName = mapName;
    }
    final GeneratedWorldResult? generated =
        WorldGenerator.generateFromMapKey(mapName);
    if (generated != null) {
      _imageIndex.addGeneratedImage(mapName, generated.toDataUrl());
    } else {
      _imageIndex.addSingleImage(mapName);
    }
  }

  void maybeSelectPlayerOrMap() {
    if (!playerSelected()) {
      String spriteName = PLAYER_SPRITES[_selectedPlayerSprite];
      _localStorage['playerSprite'] = spriteName;
      _gaReporter.reportEvent(spriteName, "PlayerSelect");
    } else if (_selectedWorldName == null) {
      final WorldThemeSpec theme =
          WORLD_THEMES[_selectedMap % WORLD_THEMES.length];
      final int seed = Random().nextInt(0x7FFFFFFF);
      final String mapFullName = encodeGeneratedMapName(theme.id, seed);
      _selectedLocally = true;
      _selectedWorldOwnerId = _network.getPeer().getId();
      _localSelectionWallTime = clock.now();
      _localSelectionTickSeconds = 0.0;
      _remoteSelectionWallTime = null;
      _remoteSelectionTickSeconds = 0.0;
      _loadSelectedWorldMap(mapFullName);
      _gaReporter.reportEvent(theme.key, "WorldSelect");
      _mapTileRects = null;

      StateUpdate mapSelected = StateUpdate()
        ..attachSingleTonUniqueDataReceipt()
        ..commanderMapSelected = mapFullName;

      _network.setAsActingCommander();
      // Preserve the compact one-time vector skybox/map descriptor (`gen:<theme>:<seed>`)
      // inside GameStateProto so all lobby peers and late-joining clients render the
      // exact same deterministic skybox and physics without transferring skybox pixels.
      _network.gameState.gameStateProto.mapName = mapFullName;

      _network.getPeer().sendSingleStateUpdate(mapSelected);
      _network.getPeer().sendSingleStateUpdate(StateUpdate()
        ..gameState = _network.gameState.gameStateProto);
    }
  }

  bool worldSelectedAndLoaded() {
    return _selectedWorldName != null &&
        _imageIndex.imageNameIsLoaded(_selectedWorldName!);
  }

  void reset() {
    if (_botName.isEmpty) {
      _localStorage.remove("playerSprite");
    }
    _selectedWorldName = null;
    _mapTileRects = null;
    _playerCardRects = null;
    _confirmButtonRect = null;
    _selectedWorldOwnerId = null;
    _selectedLocally = false;
    _localSelectionWallTime = null;
    _localSelectionTickSeconds = 0.0;
    _remoteSelectionWallTime = null;
    _remoteSelectionTickSeconds = 0.0;
    for (List s in _otherPlayersSelections) {
      s.clear();
    }
    startFadeIn();
  }

  void startFadeIn() {
    _fadeInProgress = 0.0;
    _hasRenderedOnce = false;
  }

  bool playerSelected() {
    return _localStorage.containsKey('playerSprite');
  }

  void frame(double duration) {
    try {
      final HTMLCanvasElement c = _context.canvas;
      if (c.width > 0 &&
          c.height > 0 &&
          (c.width != _width || c.height != _height)) {
        _width = c.width;
        _height = c.height;
        _spritePositions = null;
        _playerCardRects = null;
      }
    } catch (_) {}
    _animTime += duration.clamp(0.0, 0.1);
    final bool isPlayerSelect = !playerSelected();
    if (!_hasRenderedOnce || _lastFrameWasPlayerSelect != isPlayerSelect) {
      _fadeInProgress = 0.0;
      _hasRenderedOnce = true;
      _lastFrameWasPlayerSelect = isPlayerSelect;
    }
    _fadeInProgress =
        min(1.0, _fadeInProgress + duration.clamp(0.0, 0.1) * 1.65);

    if (isPlayerSelect) {
      _drawPlayerSprites(duration);
    } else {
      _drawMegaManWorldSelector(duration);
    }
    _nextSendToNetwork -= duration;
    if (_nextSendToNetwork < 0) {
      _nextSendToNetwork = UPDATE_SELECTION_TO_NETWORK_TIME;
      if (playerSelected()) {
        OtherPlayerWorldSelect selected = OtherPlayerWorldSelect()
          ..name = _localStorage['playerName']
          ..worldSelectedIndex = _selectedMap;
        _network.peer.sendDataWithKeyFramesToAll(
            GameStateUpdates()
              ..stateUpdate.add(
                  StateUpdate()..otherPlayerWorldSelect = selected));
      }
    }
  }

  double _easedFadeAlpha() {
    final double u = 1.0 - _fadeInProgress.clamp(0.0, 1.0);
    return 1.0 - u * u * u;
  }

  void _drawPlayerSprites(double duration) {
    if (_spritePositions == null || _playerCardRects == null) {
      _customMessage = null;
      _partitionSprites();
    }
    if (clearBackground) {
      _context.clearRect(0, 0, _width, _height);
    }
    final double fade = _easedFadeAlpha();
    final double slideY = (1.0 - fade) * 20.0;

    _context.save();
    _context.globalAlpha = fade;
    _context.translate(0, slideY);

    final int titleSize = (min(_width, _height) * 0.056).round().clamp(20, 42);
    final int headerY = max(26, (_height * 0.085).round());
    drawCenteredText(
        _customMessage == null
            ? "${_localStorage['playerName']} select your player!"
            : _customMessage!,
        headerY,
        titleSize);

    for (int i = 0; i < PLAYER_SPRITES.length; i++) {
      final Rectangle<double> card = _playerCardRects![i];
      final bool selected = _selectedPlayerSprite == i;
      final HTMLImageElement img = _imageIndex.getImageByName(PLAYER_SPRITES[i]);
      final int imgWidth = PLAYER_SPRITE_SIZES[i];
      final int imgHeight = max(1, img.height);
      final double maxSpriteW = card.width * 0.74;
      final double maxSpriteH = card.height * 0.74;
      final double sScale = min(maxSpriteW / imgWidth, maxSpriteH / imgHeight);
      final double drawW = imgWidth * sScale;
      final double drawH = imgHeight * sScale;
      final double cx = card.left + card.width * 0.5;
      final double cy = card.top + card.height * 0.52;

      _context.save();
      // Cartoon fighter card background + crisp border so touch hitboxes are unmistakable!
      _context.fillStyle = "rgba(8, 22, 46, 0.36)".toJS;
      _context.beginPath();
      _context.roundRect(card.left + 3, card.top + 4, card.width, card.height, 14.0.toJS);
      _context.fill();

      _context.fillStyle = (selected
              ? "rgba(28, 72, 138, 0.86)"
              : "rgba(14, 34, 68, 0.62)")
          .toJS;
      _context.beginPath();
      _context.roundRect(card.left, card.top, card.width, card.height, 14.0.toJS);
      _context.fill();

      _context.strokeStyle =
          (selected ? "#ffe44d" : "rgba(255, 255, 255, 0.42)").toJS;
      _context.lineWidth = selected ? 3.5 : 1.8;
      _context.stroke();

      if (!selected) {
        _context.globalAlpha = fade * 0.72;
        _context.drawImage(img, 0, 0, imgWidth, imgHeight, cx - drawW * 0.5,
            cy - drawH * 0.5, drawW, drawH);
      } else {
        _frameTime += duration;
        _context.globalAlpha = fade;
        final double haloR = max(drawW, drawH) * 0.68;
        final CanvasGradient halo =
            _context.createRadialGradient(cx, cy, 4, cx, cy, haloR);
        halo.addColorStop(0.0, "rgba(255, 246, 150, 0.72)");
        halo.addColorStop(0.6, "rgba(255, 255, 255, 0.24)");
        halo.addColorStop(1.0, "rgba(255, 255, 255, 0.0)");
        _context.fillStyle = halo;
        _context.beginPath();
        _context.arc(cx, cy, haloR, 0, 2 * pi);
        _context.fill();

        _context.drawImage(img, _animateX, 0, imgWidth, imgHeight,
            cx - drawW * 0.5, cy - drawH * 0.5, drawW, drawH);
        if (_frameTime > 0.25) {
          _frameTime = 0.0;
          _animateX = _animateX + imgWidth;
          if (_animateX + 5 >= img.width) {
            _animateX = 0;
          }
        }
      }
      _context.restore();
    }

    _drawActiveGameInfoBanner(fade);
    _drawConfirmActionPill("PLAY ▶", fade);
    _context.restore();
  }

  void _drawActiveGameInfoBanner(double fade) {
    final List<PlayerInfoProto> players =
        _network.getGameState().playerInfoList();
    final String? rawMap = _selectedWorldName ??
        (_network.getGameState().gameStateProto.mapName.isNotEmpty
            ? _network.getGameState().gameStateProto.mapName
            : null);
    if ((rawMap == null || rawMap.isEmpty) && players.isEmpty) {
      return;
    }

    final List<String> parts = <String>[];
    if (rawMap != null && rawMap.isNotEmpty) {
      final ParsedGeneratedMap? parsed = parseGeneratedMapName(rawMap);
      final String mapLabel = parsed?.theme.name ?? rawMap;
      parts.add("World: $mapLabel");
    }
    if (players.isNotEmpty) {
      final String names = players
          .map((PlayerInfoProto p) => p.name)
          .where((String n) => n.isNotEmpty)
          .join(", ");
      if (names.isNotEmpty) {
        parts.add("Players (${players.length}): $names");
      }
    }
    if (parts.isEmpty) {
      return;
    }

    final String bannerText = parts.join("  ·  ");
    _context.save();
    _context.globalAlpha = fade;
    final int fontPx = (_height * 0.032).round().clamp(12, 16);
    _context.font = 'bold ${fontPx}px "Trebuchet MS", Arial, sans-serif';
    _context.textAlign = "center";
    _context.textBaseline = "middle";
    final double textW = _context.measureText(bannerText).width;
    final double pillW = min(_width - 24.0, textW + 26.0);
    final double pillH = (fontPx + 12).toDouble();
    final double pillX = (_width - pillW) * 0.5;
    final double pillY =
        _height - max(10.0, _height * 0.03) - (_height * 0.105).clamp(38.0, 52.0) - pillH - 8.0;

    _context.fillStyle = "rgba(12, 24, 46, 0.84)".toJS;
    _context.strokeStyle = "rgba(255, 233, 122, 0.65)".toJS;
    _context.lineWidth = 1.6;
    _context.beginPath();
    _context.roundRect(pillX, pillY, pillW, pillH, (pillH * 0.5).toJS);
    _context.fill();
    _context.stroke();

    _context.fillStyle = "#ffe97a".toJS;
    _context.fillText(bannerText, _width * 0.5, pillY + pillH * 0.52);
    _context.restore();
  }

  void _drawConfirmActionPill(String label, double fade) {
    final double btnW = (_width * 0.28).clamp(156.0, 236.0);
    final double btnH = (_height * 0.105).clamp(38.0, 52.0);
    final double btnX = (_width - btnW) * 0.5;
    final double btnY = (_height - btnH - max(10.0, _height * 0.03));
    _confirmButtonRect = Rectangle<double>(btnX, btnY, btnW, btnH);

    _context.save();
    _context.globalAlpha = fade;
    _context.fillStyle = "rgba(8, 20, 38, 0.45)".toJS;
    _context.beginPath();
    _context.roundRect(btnX + 2, btnY + 3, btnW, btnH, (btnH * 0.5).toJS);
    _context.fill();

    final CanvasGradient grad =
        _context.createLinearGradient(0, btnY, 0, btnY + btnH);
    grad.addColorStop(0.0, "#5be870");
    grad.addColorStop(1.0, "#24a844");
    _context.fillStyle = grad;
    _context.beginPath();
    _context.roundRect(btnX, btnY, btnW, btnH, (btnH * 0.5).toJS);
    _context.fill();

    _context.strokeStyle = "#0e2216".toJS;
    _context.lineWidth = 3.2;
    _context.stroke();

    _context.strokeStyle = "#ffe97a".toJS;
    _context.lineWidth = 1.8;
    _context.beginPath();
    _context.roundRect(
        btnX + 2, btnY + 2, btnW - 4, btnH - 4, ((btnH - 4) * 0.5).toJS);
    _context.stroke();

    final int fontPx = (btnH * 0.44).round().clamp(15, 22);
    _context.font = '900 ${fontPx}px "Trebuchet MS", Arial, sans-serif';
    _context.textAlign = "center";
    _context.textBaseline = "middle";
    _context.lineJoin = "round";
    _context.strokeStyle = "#0d2214".toJS;
    _context.lineWidth = 3.6;
    _context.strokeText(label, btnX + btnW * 0.5, btnY + btnH * 0.52);
    _context.fillStyle = "#ffffff".toJS;
    _context.fillText(label, btnX + btnW * 0.5, btnY + btnH * 0.52);
    _context.restore();
  }

  List<Point<int>>? _spritePositions = null;
  double _scale = 1.0;
  int _maxWidth = -1;

  void _partitionSprites() {
    _spritePositions = [];
    _playerCardRects = [];
    for (int i = 0; i < PLAYER_SPRITES.length; i++) {
      int imgWidth = PLAYER_SPRITE_SIZES[i];
      if (_maxWidth < imgWidth) {
        _maxWidth = imgWidth;
      }
    }
    const int cols = 4;
    const int rows = 2;
    final double topMargin = max(52.0, _height * 0.165);
    final double bottomReserve = max(62.0, _height * 0.175);
    final double availH = max(140.0, _height - topMargin - bottomReserve);
    final double availW = max(240.0, _width * 0.86);
    final double gapX = min(18.0, availW * 0.028);
    final double gapY = min(16.0, availH * 0.065);
    final double cardW =
        ((availW - gapX * (cols - 1)) / cols).clamp(56.0, 175.0);
    final double cardH =
        ((availH - gapY * (rows - 1)) / rows).clamp(54.0, 155.0);
    final double gridW = cardW * cols + gapX * (cols - 1);
    final double gridH = cardH * rows + gapY * (rows - 1);
    final double startX = (_width - gridW) * 0.5;
    final double startY = topMargin + (availH - gridH) * 0.5;
    _scale = min(cardW, cardH) / _maxWidth;

    for (int i = 0; i < PLAYER_SPRITES.length; i++) {
      final int col = i % cols;
      final int row = i ~/ cols;
      final double left = startX + col * (cardW + gapX);
      final double top = startY + row * (cardH + gapY);
      _playerCardRects!.add(Rectangle<double>(left, top, cardW, cardH));
      _spritePositions!.add(Point<int>(left.round(), top.round()));
    }
  }

  /// Draws the Mega Man-style 3x3 World Boss Selector with the 8 procedural
  /// world themes ringing the chosen player sprite in the center cell!
  void _drawMegaManWorldSelector(double duration) {
    if (clearBackground) {
      _context.clearRect(0, 0, _width, _height);
    }
    final double fade = _easedFadeAlpha();
    final double slideY = (1.0 - fade) * 22.0;

    // Responsive 3x3 square grid layout centered neatly above the bottom island.
    final double headerH = max(62.0, _height * 0.115);
    final double bottomMargin = max(46.0, _height * 0.085);
    final double availH = max(210.0, _height - headerH - bottomMargin);
    final double availW = max(260.0, _width * 0.82);
    final double gap = min(18.0, min(availW, availH) * 0.036);
    final double cellSize =
        min((availH - gap * 2) / 3.0, (availW - gap * 2) / 3.0 * 0.86)
            .clamp(78.0, 176.0);
    final double tileW = cellSize * 1.18;
    final double tileH = cellSize * 0.94;
    final double gridW = tileW * 3 + gap * 2;
    final double gridH = tileH * 3 + gap * 2;
    final double originX = (_width - gridW) * 0.5;
    final double originY = headerH + (availH - gridH) * 0.5;

    _mapTileRects = List.generate(WORLD_THEMES.length, (i) {
      final Point<int> g = _GRID_COORDS[i];
      return Rectangle<double>(
        originX + g.x * (tileW + gap),
        originY + g.y * (tileH + gap),
        tileW,
        tileH,
      );
    });

    _context.save();
    _context.globalAlpha = fade;
    _context.translate(0, slideY);

    // Title banner.
    final String message = _customMessage ??
        (_network.hasOpenConnection()
            ? "HURRY! SELECT WORLD!"
            : "SELECT YOUR WORLD!");
    final int titleSize = (min(_width, _height) * 0.052).round().clamp(24, 44);
    drawCenteredText(message, (headerH * 0.58).round(), titleSize);

    // 1. Draw the 8 outer world theme tiles.
    for (int i = 0; i < WORLD_THEMES.length; i++) {
      final WorldThemeSpec theme = WORLD_THEMES[i];
      final Rectangle<double> rect = _mapTileRects![i];
      final bool selected = i == _selectedMap;
      _drawWorldThemeTile(
          theme, rect, selected, _otherPlayersSelections[i], fade);
    }

    // 2. Draw the center Mega Man player portrait tile at (1, 1)!
    final Rectangle<double> centerRect = Rectangle<double>(
      originX + (tileW + gap),
      originY + (tileH + gap),
      tileW,
      tileH,
    );
    _drawCenterPlayerTile(centerRect, duration, fade);
    _drawConfirmActionPill("DROP IN ▶", fade);

    _context.restore();
  }

  void _drawWorldThemeTile(
    WorldThemeSpec theme,
    Rectangle<double> rect,
    bool selected,
    List<String> otherPlayers,
    double fade,
  ) {
    final double pulse = sin(_animTime * 7.5) * 0.5 + 0.5;
    final double pop = selected ? (1.035 + pulse * 0.025) : 1.0;
    final double cx = rect.left + rect.width * 0.5;
    final double cy = rect.top + rect.height * 0.5;
    final double w = rect.width;
    final double h = rect.height;
    final double r = 12.0;

    _context.save();
    _context.translate(cx, cy);
    _context.scale(pop, pop);
    _context.translate(-w * 0.5, -h * 0.5);
    _context.globalAlpha = selected ? fade : fade * 0.88;

    // Cartoon drop shadow.
    _context.fillStyle = "rgba(8, 24, 52, 0.45)".toJS;
    _context.beginPath();
    _context.roundRect(4, 5, w, h, r.toJS);
    _context.fill();

    // Clipped theme mini-diorama preview artwork!
    _context.save();
    _context.beginPath();
    _context.roundRect(0, 0, w, h, r.toJS);
    _context.clip();

    final HTMLCanvasElement preview = WorldGenerator.getThemePreview(theme);
    _context.drawImage(preview, 0, 0, w, h);

    // Slight dim on unselected tiles so the active Mega Man pick jumps right out.
    if (!selected) {
      _context.fillStyle = "rgba(8, 22, 46, 0.24)".toJS;
      _context.fillRect(0, 0, w, h);
    }

    // Bottom Mega Man nameplate bar inside the frame.
    final double barH = max(22.0, h * 0.24);
    _context.fillStyle = (selected
            ? "rgba(14, 34, 68, 0.92)"
            : "rgba(12, 26, 52, 0.82)")
        .toJS;
    _context.fillRect(0, h - barH, w, barH);

    // Accent stripe along top of nameplate.
    _context.fillStyle = theme.accentColor.toJS;
    _context.fillRect(0, h - barH, w, 2.6);

    // Bold cartoon world name.
    final double nameSize = (barH * 0.58).clamp(11.0, 17.0);
    _context.font =
        "900 ${nameSize.round()}px 'Comic Sans MS', 'Trebuchet MS', Arial, sans-serif";
    _context.textAlign = "center";
    _context.textBaseline = "middle";
    _context.lineJoin = "round";
    _context.lineWidth = 3.0;
    _context.strokeStyle = "#081426".toJS;
    _context.strokeText(theme.name, w * 0.5, h - barH * 0.46);
    _context.fillStyle = (selected ? "#ffe85c" : "#ffffff").toJS;
    _context.fillText(theme.name, w * 0.5, h - barH * 0.46);

    // Special "LOW G" badge on Lunar tile!
    if (theme.badgeText.isNotEmpty) {
      final double bw = 46.0;
      final double bh = 17.0;
      final double bx = w - bw - 6.0;
      final double by = 6.0;
      _context.fillStyle = "#ffe047".toJS;
      _context.strokeStyle = "#162038".toJS;
      _context.lineWidth = 2.0;
      _context.beginPath();
      _context.roundRect(bx, by, bw, bh, 8.0.toJS);
      _context.fill();
      _context.stroke();
      _context.font = "900 10px 'Trebuchet MS', Arial, sans-serif";
      _context.fillStyle = "#141d30".toJS;
      _context.fillText(theme.badgeText, bx + bw * 0.5, by + bh * 0.54);
    }
    _context.restore();

    // Bold Mega Man comic outer border.
    _context.strokeStyle = "#0b1a30".toJS;
    _context.lineWidth = selected ? 5.0 : 3.5;
    _context.beginPath();
    _context.roundRect(0, 0, w, h, r.toJS);
    _context.stroke();

    _context.strokeStyle =
        (selected ? "#ffe44d" : "rgba(255, 255, 255, 0.55)").toJS;
    _context.lineWidth = selected ? 2.8 : 1.5;
    _context.beginPath();
    _context.roundRect(1.5, 1.5, w - 3, h - 3, (r - 1.5).toJS);
    _context.stroke();

    // Animated pulsing Mega Man corner target brackets on the selected tile!
    if (selected) {
      final double off = 4.0 + pulse * 3.5;
      final double leg = 14.0;
      _context.strokeStyle = "#fff275".toJS;
      _context.lineWidth = 3.6;
      _context.lineCap = "round";
      // Top-left
      _context.beginPath();
      _context.moveTo(-off, -off + leg);
      _context.lineTo(-off, -off);
      _context.lineTo(-off + leg, -off);
      // Top-right
      _context.moveTo(w + off - leg, -off);
      _context.lineTo(w + off, -off);
      _context.lineTo(w + off, -off + leg);
      // Bottom-left
      _context.moveTo(-off, h + off - leg);
      _context.lineTo(-off, h + off);
      _context.lineTo(-off + leg, h + off);
      // Bottom-right
      _context.moveTo(w + off - leg, h + off);
      _context.lineTo(w + off, h + off);
      _context.lineTo(w + off, h + off - leg);
      _context.stroke();
    }

    // Other multiplayer peers hovering this world tile.
    if (otherPlayers.isNotEmpty) {
      _context.font = "800 11px 'Trebuchet MS', Arial, sans-serif";
      _context.textAlign = "center";
      _context.textBaseline = "middle";
      for (int j = 0; j < otherPlayers.length; j++) {
        final String name = otherPlayers[j];
        final double tw = _context.measureText(name).width.toDouble() + 12.0;
        final double py = -12.0 - j * 18.0;
        _context.fillStyle = "rgba(18, 36, 68, 0.90)".toJS;
        _context.strokeStyle = "#5ce6ff".toJS;
        _context.lineWidth = 1.6;
        _context.beginPath();
        _context.roundRect(w * 0.5 - tw * 0.5, py - 8, tw, 16, 7.0.toJS);
        _context.fill();
        _context.stroke();
        _context.fillStyle = "#ffffff".toJS;
        _context.fillText(name, w * 0.5, py);
      }
    }

    _context.restore();
  }

  /// Draws the center Mega Man portrait tile showcasing the player's chosen
  /// animal sprite looking toward the hovered world + hovered world subtitle!
  void _drawCenterPlayerTile(
      Rectangle<double> rect, double duration, double fade) {
    final double w = rect.width;
    final double h = rect.height;
    final double r = 14.0;
    final WorldThemeSpec hovered =
        WORLD_THEMES[_selectedMap % WORLD_THEMES.length];
    final Point<int> hoveredGrid = _GRID_COORDS[_selectedMap % _GRID_COORDS.length];

    _context.save();
    _context.translate(rect.left, rect.top);
    _context.globalAlpha = fade;

    // Drop shadow.
    _context.fillStyle = "rgba(8, 24, 52, 0.45)".toJS;
    _context.beginPath();
    _context.roundRect(4, 5, w, h, r.toJS);
    _context.fill();

    // Radial glowing cartoon hero backdrop inside the center square.
    _context.save();
    _context.beginPath();
    _context.roundRect(0, 0, w, h, r.toJS);
    _context.clip();

    final CanvasGradient bg =
        _context.createRadialGradient(w * 0.5, h * 0.44, 6, w * 0.5, h * 0.44, w * 0.72);
    bg.addColorStop(0.0, "#3a92e8");
    bg.addColorStop(0.6, "#1a529c");
    bg.addColorStop(1.0, "#0e2954");
    _context.fillStyle = bg;
    _context.fillRect(0, 0, w, h);

    // Subtle spinning golden hero sunburst behind the chosen animal!
    _context.save();
    _context.translate(w * 0.5, h * 0.45);
    _context.rotate(_animTime * 0.45);
    for (int i = 0; i < 10; i++) {
      final double a0 = (i / 10.0) * 2 * pi;
      _context.fillStyle = "rgba(255, 236, 120, 0.16)".toJS;
      _context.beginPath();
      _context.moveTo(0, 0);
      _context.arc(0, 0, w * 0.75, a0, a0 + 0.22);
      _context.closePath();
      _context.fill();
    }
    _context.restore();

    // Draw the chosen player sprite animated in the center!
    final String? spriteName = _localStorage['playerSprite'];
    if (spriteName != null && _imageIndex.imageNameIsLoaded(spriteName)) {
      final HTMLImageElement img = _imageIndex.getImageByName(spriteName);
      final int frameW = playerSpriteWidth(spriteName);
      final int imgH = img.height;
      if (frameW > 0 && imgH > 0) {
        _frameTime += duration;
        if (_frameTime > 0.22) {
          _frameTime = 0.0;
          _animateX += frameW;
          if (_animateX + 5 >= img.width) {
            _animateX = 0;
          }
        }
        final double maxDrawH = h * 0.52;
        final double maxDrawW = w * 0.56;
        final double spriteScale = min(maxDrawW / frameW, maxDrawH / imgH);
        final double drawW = frameW * spriteScale;
        final double drawH = imgH * spriteScale;
        final double bob = sin(_animTime * 4.5) * 3.0;
        final bool lookLeft = hoveredGrid.x == 0;

        _context.save();
        _context.translate(w * 0.5, h * 0.46 + bob);
        if (lookLeft) {
          _context.scale(-1, 1);
        }
        _context.drawImage(
            img, _animateX, 0, frameW, imgH, -drawW * 0.5, -drawH * 0.5, drawW, drawH);
        _context.restore();
      }
    }

    // Top player name pill inside the center square.
    final String playerName = _localStorage['playerName'] ?? 'PLAYER';
    _context.font = "900 12px 'Trebuchet MS', Arial, sans-serif";
    _context.textAlign = "center";
    _context.textBaseline = "middle";
    _context.lineJoin = "round";
    _context.lineWidth = 3.0;
    _context.strokeStyle = "#081426".toJS;
    _context.strokeText(playerName, w * 0.5, 13.0);
    _context.fillStyle = "#ffffff".toJS;
    _context.fillText(playerName, w * 0.5, 13.0);

    // Bottom info banner showing the currently hovered world's subtitle!
    final double barH = max(22.0, h * 0.24);
    _context.fillStyle = "rgba(10, 22, 46, 0.90)".toJS;
    _context.fillRect(0, h - barH, w, barH);
    _context.fillStyle = hovered.accentColor.toJS;
    _context.fillRect(0, h - barH, w, 2.6);

    final double subSize = (barH * 0.54).clamp(10.0, 15.0);
    _context.font = "800 ${subSize.round()}px 'Trebuchet MS', Arial, sans-serif";
    _context.strokeStyle = "#081426".toJS;
    _context.lineWidth = 2.6;
    _context.strokeText(hovered.subtitle, w * 0.5, h - barH * 0.46);
    _context.fillStyle = (hovered.isLowGravity ? "#ffe44d" : "#d8f4ff").toJS;
    _context.fillText(hovered.subtitle, w * 0.5, h - barH * 0.46);

    _context.restore();

    // Bold golden-ink Mega Man center frame border.
    _context.strokeStyle = "#0b1a30".toJS;
    _context.lineWidth = 4.6;
    _context.beginPath();
    _context.roundRect(0, 0, w, h, r.toJS);
    _context.stroke();

    _context.strokeStyle = "#5ce6ff".toJS;
    _context.lineWidth = 2.4;
    _context.beginPath();
    _context.roundRect(1.5, 1.5, w - 3, h - 3, (r - 1.5).toJS);
    _context.stroke();

    _context.restore();
  }

  void drawCenteredText(String text, [int y = 0, int size = 20]) {
    _context.save();
    if (clearBackground) {
      _context.clearRect(0, 0, _width, _height);
    }
    _context.font =
        "800 ${size}px 'Comic Sans MS', 'Trebuchet MS', Arial, sans-serif";
    _context.textAlign = "center";
    _context.textBaseline = "middle";
    _context.lineJoin = "round";
    _context.fillStyle = "rgba(8, 36, 72, 0.35)".toJS;
    _context.fillText(text, _width / 2 + 3, y + 4);
    _context.lineWidth = max(4.0, size * 0.14);
    _context.strokeStyle = "#0b2442".toJS;
    _context.strokeText(text, _width / 2, y);
    _context.fillStyle = "#ffffff".toJS;
    _context.fillText(text, _width / 2, y);
    _context.restore();
  }

  void setMapForTest(String name) {
    _selectedWorldName = name;
    _selectedWorldOwnerId = null;
    _selectedLocally = false;
    _localSelectionWallTime = null;
    _localSelectionTickSeconds = 0.0;
    _remoteSelectionWallTime = null;
    _remoteSelectionTickSeconds = 0.0;
  }

  void registerRollbackHandler(
      void Function(String winnerId, String winnerMapName) handler) {
    _onRollbackMapSelection = handler;
  }

  void tickTieBreakTimer(double duration) {
    if (duration <= 0.0) {
      return;
    }
    if (_localSelectionWallTime != null) {
      _localSelectionTickSeconds += duration;
    }
    if (_remoteSelectionWallTime != null) {
      _remoteSelectionTickSeconds += duration;
    }
  }

  String? get selectedWorldOwnerId => _selectedWorldOwnerId;

  void setSelectedMapIndexForTest(int index) {
    _selectedMap = index % PlayerWorldSelector.AVAILABLE_MAPS.length;
  }

  CommanderTieBreakOutcome resolveIncomingCommanderGameState(
      ConnectionWrapper connection, GameStateProto newGameState) {
    if (newGameState.actingCommanderId != connection.id) {
      return CommanderTieBreakOutcome.none;
    }
    final String remoteId = connection.id;
    final String localId = _network.getPeer().getId() ?? '';

    if (_selectedLocally) {
      if (_isWithinLocalTieBreakWindow() &&
          remoteId.compareTo(localId) > 0) {
        PlayerWorldSelector._log.info(
            "GameState tie-break won by higher natural ID '$remoteId' over '$localId'; rolling back local selection.");
        _applyRemoteWinningSelection(remoteId, newGameState.mapName);
        return CommanderTieBreakOutcome.remoteWinsRollbackToRemote;
      }
      if (_isWithinLocalInFlightGrace() &&
          localId.compareTo(remoteId) > 0) {
        _resendLocalWinningMapTo(connection);
        return CommanderTieBreakOutcome.localWinsIgnoreRemote;
      }
      return CommanderTieBreakOutcome.none;
    }

    if (_selectedWorldName != null && _selectedWorldOwnerId != null) {
      final String currentOwner = _selectedWorldOwnerId!;
      if (_isWithinRemoteTieBreakWindow() &&
          remoteId.compareTo(currentOwner) > 0) {
        _applyRemoteWinningSelection(remoteId, newGameState.mapName);
        return CommanderTieBreakOutcome.remoteWinsRollbackToRemote;
      }
      if (_isWithinRemoteInFlightGrace() &&
          currentOwner.compareTo(remoteId) > 0) {
        return CommanderTieBreakOutcome.localWinsIgnoreRemote;
      }
    }
    return CommanderTieBreakOutcome.none;
  }
}

enum CommanderTieBreakOutcome {
  none,
  localWinsIgnoreRemote,
  remoteWinsRollbackToRemote,
}
