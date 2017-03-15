import 'package:di/di.dart';
import 'dart:math';
import 'world_data.dart';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/net/net.dart';
import 'package:dart2d/res/imageindex.dart';

@Injectable()
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
  }

  var _context;
  Map _localStorage;
  KeyState _keyState;
  MobileControls _mobileControls;
  ImageIndex _imageIndex;
  Network _network;
  GaReporter _gaReporter;
  PacketListenerBindings _packetListenerBindings;
  int _width;
  int _height;

  int _selectedPlayerSprite = new Random().nextInt(PLAYER_SPRITES.length);
  int _animateX = 0;
  double _frameTime = 0.00;

  int _selectedMap = new Random().nextInt(AVAILABLE_MAPS.length);

  String _selectedWorldName = null;
  String get selectedWorldName => _selectedWorldName;

  String _customMessage = null;

  double _nextSendToNetwork = 0.0;

  PlayerWorldSelector(
      this._packetListenerBindings,
      this._network,
      this._mobileControls,
      this._imageIndex,
      this._gaReporter,
      @LocalStorage() Map storage,
      @LocalKeyState() KeyState localKeyState,
      @WorldCanvas() Object canvasElement) {
    var canvas = canvasElement;
    _context = canvas.context2D;
    _width = canvas.width;
    _height = canvas.height;
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
    _keyState.registerListener(KeyCodeDart.SPACE, _selectPlayer);
    _keyState.registerListener(KeyCodeDart.ENTER, _selectPlayer);
    _keyState.registerListener(KeyCodeDart.CTRL, _selectPlayer);
    _keyState.registerListener(KeyCodeDart.SPACE, _selectMap);
    _keyState.registerListener(KeyCodeDart.ENTER, _selectMap);
    _keyState.registerListener(KeyCodeDart.CTRL, _selectMap);
    _mobileControls.listenForTouch((int x, int y) {
      if (_spritePositions != null && !playerSelected()) {
        double scaledWidth = _maxWidth * _scale;
        for (int i = 0; i < PLAYER_SPRITES.length; i++) {
          if (_onPoint(_spritePositions[i], x, y, scaledWidth)) {
            if (_selectedPlayerSprite == i) {
              _selectPlayer();
            } else {
              _selectedPlayerSprite = i;
              _customMessage = "Touch again to confirm!";
            }
          }
        }
      } else if (_mapPositions != null) {
        double scaledWidth = _maxMapWidth * _mapScale;
        for (int i = 0; i < AVAILABLE_MAPS.length; i++) {
          if (_onPoint(_mapPositions[i], x, y, scaledWidth)) {
            if (_selectedMap == i) {
              _selectMap();
            } else {
              _selectedMap = i;
              _customMessage = "Touch again to confirm!";
            }
          }
        }
      }
    });
    _packetListenerBindings.bindHandler(OTHER_PLAYER_WORLD_SELECT,
        (ConnectionWrapper connection, List data) {
      String playerName = data[0];
      int selectedIndex = data[1];
      // Clear up existing selection.
      for (List existingSelection in _otherPlayersSelections) {
        existingSelection.remove(playerName);
      }
      if (_otherPlayersSelections.length > selectedIndex) {
        _otherPlayersSelections[selectedIndex].add(playerName);
      }
    });
    // TODO Always remove, change this behavior.
    _localStorage.remove('playerSprite');
  }

  bool _onPoint(Point<int> p, int x, int y, double scaledWidth) {
    if (x >= p.x && x <= p.x + scaledWidth) {
      if (y >= p.y && y <= p.y + scaledWidth) {
        return true;
      }
    }
    return false;
  }

  void _selectPlayer() {
    if (!playerSelected()) {
      String spriteName = PLAYER_SPRITES[_selectedPlayerSprite];
      _localStorage['playerSprite'] = spriteName;
      _gaReporter.reportEvent(spriteName, "PlayerSelect");
    }
  }

  void _selectMap() {
    if (playerSelected() && _mapPositions != null) {
      String mapFullName = WORLDS[AVAILABLE_MAPS[_selectedMap]];
      _imageIndex.addSingleImage(mapFullName);
      _selectedWorldName = mapFullName;
      _gaReporter.reportEvent(_selectedWorldName, "WorldSelect");
    }
  }

  bool worldSelectedAndLoaded() {
    return _selectedWorldName != null &&
        _imageIndex.imageNameIsLoaded(_selectedWorldName);
  }

  void reset() {
    _localStorage.remove("playerSprite");
    _selectedWorldName = null;
  }

  bool playerSelected() {
    return _localStorage.containsKey('playerSprite');
  }

  void frame(double duration) {
    if (!playerSelected()) {
      _drawPlayerSprites(duration);
    } else {
      _drawMaps();
    }
    _nextSendToNetwork -= duration;
    if (_nextSendToNetwork < 0) {
      _nextSendToNetwork = UPDATE_SELECTION_TO_NETWORK_TIME;
      if (playerSelected()) {
        _network.peer.sendDataWithKeyFramesToAll({
          OTHER_PLAYER_WORLD_SELECT: [_localStorage['playerName'], _selectedMap]
        });
      }
    }
  }

  void _drawPlayerSprites(double duration) {
    if (_spritePositions == null) {
      _customMessage = null;
      _partitionSprites();
    }
    _context.clearRect(0, 0, _width, _height);
    drawCenteredText(
        _customMessage == null
            ? "${_localStorage['playerName']} select your player!"
            : _customMessage,
        (_height / 2 - _height / 8).toInt(),
        50);
    for (int i = 0; i < PLAYER_SPRITES.length; i++) {
      Point<int> position = _spritePositions[i];
      var img = _imageIndex.getImageByName(PLAYER_SPRITES[i]);
      int imgWidth = PLAYER_SPRITE_SIZES[i];
      int height = img.height;

      _context.save();
      if (_selectedPlayerSprite != i) {
        _context.globalAlpha = 0.5;
        _context.drawImageScaledFromSource(img, 0, 0, imgWidth, height,
            position.x, position.y, imgWidth * _scale, height * _scale);
      } else {
        _frameTime += duration;
        _context.globalAlpha = 1.0;
        _context.drawImageScaledFromSource(img, _animateX, 0, imgWidth, height,
            position.x, position.y, imgWidth * _scale, height * _scale);
        if (_frameTime > 0.25) {
          _frameTime = 0.0;
          _animateX = _animateX + imgWidth;
          if (_animateX >= img.width) {
            _animateX = 0;
          }
        }
      }
      _context.restore();
    }
  }

  List<Point<int>> _spritePositions = null;
  double _scale;
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
      _spritePositions.add(new Point(x, y));
      x += _maxWidth * _scale;
    }
  }

  void _drawMaps() {
    if (_mapPositions == null) {
      _customMessage = null;
      _partitionMaps();
    }
    _context.clearRect(0, 0, _width, _height);
    String message = "Select world!";
    if (_network.hasOpenConnection()) {
      message = "Hurry to select world!";
    }
    drawCenteredText(
        _customMessage == null
            ? message
            : _customMessage,
        (_height / 2 - _height / 8).toInt(),
        50);
    for (int i = 0; i < AVAILABLE_MAPS.length; i++) {
      List<String> otherPlayersSelections = _otherPlayersSelections[i];
      Point<int> position = _mapPositions[i];
      var img = _imageIndex.getImageByName(AVAILABLE_MAPS[i]);

      double selectScale = _mapScale;
      double xOffset = 0.0;
      _context.save();
      if (_selectedMap != i) {
        _context.globalAlpha = 0.3;
      } else {
        _context.globalAlpha = 1.0;
        selectScale *= 1.5;
        xOffset = _mapScale * img.width / 2;
      }
      double x =  position.x - xOffset;
      double drawWidth = img.width * selectScale;
      if (!otherPlayersSelections.isEmpty) {
        _context.save();
        _context.globalAlpha = 0.7;
        _context.font = "12px Arial";
        for (int i = 0; i < otherPlayersSelections.length; i ++) {
          String playerName = otherPlayersSelections[i];
          var metrics = _context.measureText(playerName);
          _context.fillText(playerName, x  + drawWidth /2 - metrics.width / 2, position.y - 20 * i - 20);
        }
        _context.restore();
      }
      _context.drawImageScaledFromSource(
          img,
          0,
          0,
          img.width,
          img.height,
          x,
          position.y,
          drawWidth,
          img.height * selectScale);
      _context.restore();
    }
  }

  List<Point<int>> _mapPositions = null;
  List<List<String>> _otherPlayersSelections = [];
  double _mapScale;
  int _maxMapWidth = -1;

  void _partitionMaps() {
    _mapPositions = [];
    for (String miniMap in WORLDS.keys) {
      var img = _imageIndex.getImageByName(miniMap);
      assert(img != null);
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
      _mapPositions.add(new Point(x, y));
      _otherPlayersSelections.add([]);
      x += _maxMapWidth * _mapScale;
    }
  }

  void drawCenteredText(String text, [int y, int size = 20]) {
    if (y == null) {
      y = _height ~/ 2;
    }
    _context.clearRect(0, 0, _width, _height);
    _context.setFillColorRgb(-0, 0, 0);
    _context.font = "${size}px Arial";
    var metrics = _context.measureText(text);
    _context.fillText(text, _width / 2 - metrics.width / 2, y);
    _context.save();
  }

  void setMapForTest(String name) {
    _selectedWorldName = name;
  }
}
