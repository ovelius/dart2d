import 'dart:js_interop';
import 'dart:math';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/net/state_updates.pb.dart';
import 'package:injectable/injectable.dart';
import 'package:web/web.dart';

import '../net/connection.dart';
import '../net/helpers.dart';
import '../net/network.dart';
import 'world_data.dart';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/res/imageindex.dart';

@Singleton(scope: 'world')
class PlayerWorldSelector {
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
  static final List<int> PLAYER_SPRITE_SIZES = [97, 96, 98, 93, 77, 88, 97, 95];

  static final List<String> AVAILABLE_MAPS = new List.from(WORLDS.keys);

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

  int _selectedMap = new Random().nextInt(AVAILABLE_MAPS.length);

  String? _selectedWorldName = null;
  String? get selectedWorldName => _selectedWorldName;

  String? _customMessage = null;

  double _nextSendToNetwork = 0.0;
  bool clearBackground = true;
  double _fadeInProgress = 0.0;
  bool _lastFrameWasPlayerSelect = false;
  bool _hasRenderedOnce = false;

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
      _selectedPlayerSprite =
          (_selectedPlayerSprite - 1 + PLAYER_SPRITES.length) %
              PLAYER_SPRITES.length;
      _selectedMap =
          (_selectedMap - 1 + AVAILABLE_MAPS.length) % AVAILABLE_MAPS.length;
    });
    _keyState.registerListener(KeyCodeDart.RIGHT, () {
      _animateX = 0;
      _selectedPlayerSprite =
          (_selectedPlayerSprite + 1) % PLAYER_SPRITES.length;
      _selectedMap = (_selectedMap + 1) % AVAILABLE_MAPS.length;
    });
    _keyState.registerListener(KeyCodeDart.SPACE, maybeSelectPlayerOrMap);
    _keyState.registerListener(KeyCodeDart.ENTER, maybeSelectPlayerOrMap);
    _keyState.registerListener(KeyCodeDart.CTRL, maybeSelectPlayerOrMap);
    _mobileControls.listenForTouch((int x, int y) {
      if (_spritePositions != null && !playerSelected()) {
        double scaledWidth = _maxWidth * _scale;
        for (int i = 0; i < PLAYER_SPRITES.length; i++) {
          if (_onPoint(_spritePositions![i], x, y, scaledWidth)) {
            if (_selectedPlayerSprite == i) {
              maybeSelectPlayerOrMap();
            } else {
              _selectedPlayerSprite = i;
              _customMessage = "Touch again to confirm!";
            }
          }
        }
      } else if (_mapPositions != null) {
        double scaledWidth = _maxMapWidth * _mapScale;
        for (int i = 0; i < AVAILABLE_MAPS.length; i++) {
          if (_onPoint(_mapPositions![i], x, y, scaledWidth)) {
            if (_selectedMap == i) {
              // This always selects even if already loaded...
              maybeSelectPlayerOrMap();
            } else {
              _selectedMap = i;
              _customMessage = "Touch again to confirm!";
            }
          }
        }
      }
    });
    _packetListenerBindings.bindHandler(StateUpdate_Update.otherPlayerWorldSelect,
        (ConnectionWrapper connection, StateUpdate update) {
      String playerName = update.otherPlayerWorldSelect.name;
      int selectedIndex = update.otherPlayerWorldSelect.worldSelectedIndex;
      // Clear up existing selection.
      for (List existingSelection in _otherPlayersSelections) {
        existingSelection.remove(playerName);
      }
      if (_otherPlayersSelections.length > selectedIndex) {
        _otherPlayersSelections[selectedIndex].add(playerName);
      }
    });
    _packetListenerBindings.bindHandler(StateUpdate_Update.commanderMapSelected,
            (ConnectionWrapper connection, StateUpdate update) {
      _selectedWorldName = update.commanderMapSelected;
      _imageIndex.addSingleImage(_selectedWorldName!);
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

  bool _onPoint(Point<int> p, int x, int y, double scaledWidth) {
    if (x >= p.x && x <= p.x + scaledWidth) {
      if (y >= p.y && y <= p.y + scaledWidth) {
        return true;
      }
    }
    return false;
  }

  void maybeSelectPlayerOrMap() {
    if (!playerSelected()) {
      String spriteName = PLAYER_SPRITES[_selectedPlayerSprite];
      _localStorage['playerSprite'] = spriteName;
      _gaReporter.reportEvent(spriteName, "PlayerSelect");
    } else if (_selectedWorldName == null) {
      String mapFullName = WORLDS[AVAILABLE_MAPS[_selectedMap]]!;
      _imageIndex.addSingleImage(mapFullName);
      _selectedWorldName = mapFullName;
      _gaReporter.reportEvent(_selectedWorldName!, "WorldSelect");
      _mapPositions = null;

      StateUpdate mapSelected = StateUpdate()
        ..attachSingleTonUniqueDataReceipt()
        ..commanderMapSelected = mapFullName;

      _network.setAsActingCommander();

      _network.getPeer().sendSingleStateUpdate(mapSelected);
      _network.getPeer().sendSingleStateUpdate(StateUpdate()
        ..gameState = _network.gameState.gameStateProto);
    }
  }

  bool worldSelectedAndLoaded() {
    return _selectedWorldName != null && _imageIndex.imageNameIsLoaded(_selectedWorldName!);
  }

  void reset() {
    if (_botName.isEmpty) {
      _localStorage.remove("playerSprite");
    }
    _selectedWorldName = null;
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
    final bool isPlayerSelect = !playerSelected();
    if (!_hasRenderedOnce || _lastFrameWasPlayerSelect != isPlayerSelect) {
      _fadeInProgress = 0.0;
      _hasRenderedOnce = true;
      _lastFrameWasPlayerSelect = isPlayerSelect;
    }
    _fadeInProgress = min(1.0, _fadeInProgress + duration.clamp(0.0, 0.1) * 1.65);

    if (isPlayerSelect) {
      _drawPlayerSprites(duration);
    } else {
      _drawMaps();
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
                ..stateUpdate.add(StateUpdate()..otherPlayerWorldSelect =
                    selected)
        );
      }
    }
  }

  double _easedFadeAlpha() {
    final double u = 1.0 - _fadeInProgress.clamp(0.0, 1.0);
    return 1.0 - u * u * u;
  }

  void _drawPlayerSprites(double duration) {
    if (_spritePositions == null) {
      _customMessage = null;
      _partitionSprites();
    }
    if (clearBackground) {
      _context.clearRect(0, 0, _width, _height);
    }
    final double fade = _easedFadeAlpha();
    final double slideY = (1.0 - fade) * 26.0;

    _context.save();
    _context.globalAlpha = fade;
    _context.translate(0, slideY);

    drawCenteredText(
        _customMessage == null
            ? "${_localStorage['playerName']} select your player!"
            : _customMessage!,
        (_height / 2 - _height / 8).toInt(),
        50);
    for (int i = 0; i < PLAYER_SPRITES.length; i++) {
      Point<int> position = _spritePositions![i];
      HTMLImageElement img = _imageIndex.getImageByName(PLAYER_SPRITES[i]);
      int imgWidth = PLAYER_SPRITE_SIZES[i];
      int height = img.height;
      double drawW = imgWidth * _scale;
      double drawH = height * _scale;
      _context.save();
      if (_selectedPlayerSprite != i) {
        _context.globalAlpha = fade * 0.55;
        _context.drawImage(img, 0, 0, imgWidth, height,
            position.x, position.y, drawW, drawH);
      } else {
        _frameTime += duration;
        _context.globalAlpha = fade;
        // Sunny cartoon spotlight halo behind the selected player sprite.
        double cx = position.x + drawW * 0.5;
        double cy = position.y + drawH * 0.5;
        double haloR = max(drawW, drawH) * 0.72;
        CanvasGradient halo = _context.createRadialGradient(cx, cy, 4, cx, cy, haloR);
        halo.addColorStop(0.0, "rgba(255, 246, 150, 0.72)");
        halo.addColorStop(0.6, "rgba(255, 255, 255, 0.26)");
        halo.addColorStop(1.0, "rgba(255, 255, 255, 0.0)");
        _context.fillStyle = halo;
        _context.beginPath();
        _context.arc(cx, cy, haloR, 0, 2 * pi);
        _context.fill();

        _context.drawImage(img, _animateX, 0, imgWidth, height,
            position.x, position.y, drawW, drawH);
        if (_frameTime > 0.25) {
          _frameTime = 0.0;
          _animateX = _animateX + imgWidth;
          // Next frame clearly runs outside the image... so +5.
          if (_animateX + 5 >= img.width) {
            _animateX = 0;
          }
        }
      }
      _context.restore();
    }
    _context.restore();
  }

  List<Point<int>>? _spritePositions = null;
   double _scale = 1.0;
  int _maxWidth = -1;

  void _partitionSprites() {
    _spritePositions = [];
    for (int i = 0; i < PLAYER_SPRITES.length; i++) {
      int imgWidth = PLAYER_SPRITE_SIZES[i];
      if (_maxWidth < imgWidth) {
        _maxWidth = imgWidth;
      }
    }
    // TODO split in multiple rows?
    int allSpriteWidth = _maxWidth * PLAYER_SPRITES.length;
    // Scale to fit 3/4 of screen.
    _scale = ((_width / 4) * 3) / allSpriteWidth;
    double x = _width / 2 - (allSpriteWidth / 2 * _scale);
    int y = _height ~/ 2 + _height ~/ 8;

    for (int i = 0; i < PLAYER_SPRITES.length; i++) {
      _spritePositions!.add(new Point(x.toInt(), y));
      x += _maxWidth * _scale;
    }
  }

  void _drawMaps() {
    if (_mapPositions == null) {
      _customMessage = null;
      _partitionMaps();
    }
    if (clearBackground) {
      _context.clearRect(0, 0, _width, _height);
    }
    final double fade = _easedFadeAlpha();
    final double slideY = (1.0 - fade) * 24.0;

    _context.save();
    _context.globalAlpha = fade;
    _context.translate(0, slideY);

    String message = "Select world!";
    if (_network.hasOpenConnection()) {
      message = "Hurry to select world!";
    }
    drawCenteredText(
        _customMessage == null
            ? message
            : _customMessage!,
        (_height / 2 - _height / 8).toInt(),
        50);
    for (int i = 0; i < AVAILABLE_MAPS.length; i++) {
      List<String> otherPlayersSelections = _otherPlayersSelections[i];
      Point<int> position = _mapPositions![i];
      HTMLImageElement img = _imageIndex.getImageByName(AVAILABLE_MAPS[i]);

      double selectScale = _mapScale;
      double xOffset = 0.0;
      _context.save();
      if (_selectedMap != i) {
        _context.globalAlpha = fade * 0.42;
      } else {
        _context.globalAlpha = fade;
        selectScale *= 1.5;
        xOffset = _mapScale * img.width / 2;
      }
      double x = position.x - xOffset;
      double drawWidth = img.width * selectScale;
      double drawHeight = img.height * selectScale;
      if (!otherPlayersSelections.isEmpty) {
        _context.save();
        _context.globalAlpha = fade * 0.92;
        _context.font = "700 13px 'Trebuchet MS', Arial, sans-serif";
        _context.lineJoin = "round";
        _context.lineWidth = 3.0;
        _context.strokeStyle = "#0b2442".toJS;
        _context.fillStyle = "#ffffff".toJS;
        for (int j = 0; j < otherPlayersSelections.length; j++) {
          String playerName = otherPlayersSelections[j];
          var metrics = _context.measureText(playerName);
          double tx = x + drawWidth / 2 - metrics.width / 2;
          double ty = position.y - 20 * j - 20;
          _context.strokeText(playerName, tx, ty);
          _context.fillText(playerName, tx, ty);
        }
        _context.restore();
      }
      if (_selectedMap == i) {
        // Cartoon frame highlight around the selected map preview.
        _context.strokeStyle = "#ffe05c".toJS;
        _context.lineWidth = 5.0;
        _context.strokeRect(x - 3, position.y - 3, drawWidth + 6, drawHeight + 6);
      }
      _context.drawImage(
          img,
          0,
          0,
          img.width,
          img.height,
          x,
          position.y,
          drawWidth,
          drawHeight);
      _context.restore();
    }
    _context.restore();
  }

  List<Point<int>>? _mapPositions = null;
  List<List<String>> _otherPlayersSelections = [];
  double _mapScale = 1.0;
  int _maxMapWidth = -1;

  void _partitionMaps() {
    _mapPositions = [];
    for (String miniMap in WORLDS.keys) {
      HTMLImageElement img = _imageIndex.getImageByName(miniMap);
      if (_maxMapWidth < img.width) {
        _maxMapWidth = img.width;
      }
    }
    int allMapWidth = _maxMapWidth * WORLDS.length;
    // Scale to fit screen
    _mapScale = _width / allMapWidth;
    double x = _width / 2 - (allMapWidth / 2 * _mapScale);
    int y = _height ~/ 2 + _height ~/ 8;

    for (String miniMap in WORLDS.keys) {
      _mapPositions!.add(new Point(x.toInt(), y));
      _otherPlayersSelections.add([]);
      x += _maxMapWidth * _mapScale;
    }
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
    // Cartoon drop shadow + bold dark ink outline + bright white/gold fill.
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
  }
}
