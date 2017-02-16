import 'package:di/di.dart';
import 'dart:math';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/res/imageindex.dart';

@Injectable()
class PlayerWorldSelector {
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

  static final Map<String, String> WORLDS = {
    "world_map_mini.png": "world_map.png",
    "world_house_mini.png": "world_house.png",
    "world_cloud_mini.png": "world_cloud.png",
    "world_maze_mini.png": "world_maze.png",
    "world_town_mini.png": "world_town.png",
  };

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
  int _width;
  int _height;

  int _selectedPlayerSprite = new Random().nextInt(PLAYER_SPRITES.length);
  int _animateX = 0;
  double _frameTime = 0.00;

  int _selectedMap = new Random().nextInt(AVAILABLE_MAPS.length);


  String _selectedWorldName = null;
  String get selectedWorldName => _selectedWorldName;

  String _customMessage = null;

  PlayerWorldSelector(
      @LocalStorage() Map storage,
      ImageIndex imageIndex,
      @LocalKeyState() KeyState localKeyState,
      MobileControls mobileControls,
      @WorldCanvas() Object canvasElement) {
    this._imageIndex = imageIndex;
    this._mobileControls = mobileControls;
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
      _localStorage['playerSprite'] = PLAYER_SPRITES[_selectedPlayerSprite];
    }
  }

  void _selectMap() {
    if (playerSelected() && _mapPositions != null) {
      String mapFullName = WORLDS[AVAILABLE_MAPS[_selectedMap]];
      _imageIndex.addSingleImage(mapFullName);
      _selectedWorldName = mapFullName;
    }
  }

  bool worldSelectedAndLoaded() {
    return _selectedWorldName != null && _imageIndex.imageNameIsLoaded(_selectedWorldName);
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
    drawCenteredText(
        _customMessage == null
            ? "Looks like you are the first. Select arena!"
            : _customMessage,
        (_height / 2 - _height / 8).toInt(),
        50);
    for (int i = 0; i < AVAILABLE_MAPS.length; i++) {
      Point<int> position = _mapPositions[i];
      var img = _imageIndex.getImageByName(AVAILABLE_MAPS[i]);

      double selectScale = _mapScale;
      double xOffset = 0.0;
      _context.save();
      if (_selectedMap != i) {
        _context.globalAlpha = 0.3;
      } else {
        _context.globalAlpha = 1.0;
        selectScale *= 2.0;
        xOffset = _mapScale * img.width / 2;
      }
      _context.drawImageScaledFromSource(img, 0, 0, img.width, img.height,
          position.x - xOffset, position.y, img.width * selectScale, img.height * selectScale);
      _context.restore();
    }
  }

  List<Point<int>> _mapPositions = null;
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
