import 'package:di/di.dart';
import 'dart:math';
import 'package:dart2d/util/util.dart';
import 'package:dart2d/bindings/annotations.dart';
import 'package:dart2d/res/imageindex.dart';

@Injectable()
class PlayerWorldSelector {

  static final List<String> PLAYER_SPRITES = [
    "sheep98.png" ,
    "ele96.png" ,
    "donkey98.png" ,
    "goat93.png" ,
    "cock77.png",
    "lion88.png",
    "dra98.png",
    "turtle96.png"];
  static final List<int> PLAYER_SPRITE_SIZES = [97, 96, 98, 93, 77, 88, 97, 95];

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
  ImageIndex _imageIndex;
  int _width;
  int _height;

  int _selectedPlayerSprite = new Random().nextInt(PLAYER_SPRITES.length);
  int _animateX = 0;
  double _frameTime = 0.00;

  PlayerWorldSelector(
      @LocalStorage() Map storage,
      ImageIndex imageIndex,
      @LocalKeyState() KeyState localKeyState,
      @WorldCanvas() Object canvasElement) {
    // Hack the typesystem.
    this._imageIndex = imageIndex;
    var canvas = canvasElement;
    _context = canvas.context2D;
    _width = canvas.width;
    _height = canvas.height;
    _localStorage = storage;
    _keyState = localKeyState;
    _keyState.registerListener(KeyCodeDart.LEFT, (){
        _animateX = 0;
        _selectedPlayerSprite =
            (_selectedPlayerSprite - 1 + PLAYER_SPRITES.length) %
                PLAYER_SPRITES.length;
    });
    _keyState.registerListener(KeyCodeDart.RIGHT, (){

        _animateX = 0;
        _selectedPlayerSprite =
            (_selectedPlayerSprite + 1) % PLAYER_SPRITES.length;
    });
    _keyState.registerListener(KeyCodeDart.SPACE, _selectPlayer);
    _keyState.registerListener(KeyCodeDart.ENTER, _selectPlayer);
    _keyState.registerListener(KeyCodeDart.CTRL, _selectPlayer);
  }

  void _selectPlayer() {
    _localStorage['playerSprite'] = PLAYER_SPRITES[_selectedPlayerSprite];
  }

  void frame(double duration) {
    _drawPlayerSprites(duration);
  }

  void _drawPlayerSprites(double duration) {
    _context.clearRect(0, 0, _width, _height);
    drawCenteredText("${_localStorage['playerName']} select your player!", (_height /2 - _height / 8).toInt(), 50);
    int betweenDistance = _width ~/ (PLAYER_SPRITES.length * 2);
    int x = betweenDistance;
    for (int i = 0; i < PLAYER_SPRITES.length; i++) {
      int imgWidth = PLAYER_SPRITE_SIZES[i];
      var img = _imageIndex.getImageByName(PLAYER_SPRITES[i]);
      int height = img.height;
      double y = _height /2 + _height / 8;

      _context.save();
      if (_selectedPlayerSprite != i) {
        _context.globalAlpha = 0.5;
        _context.drawImageScaledFromSource(img,
            0, 0, imgWidth, height,
            x, y,
            imgWidth, height);
      } else {
        _frameTime += duration;
        _context.globalAlpha = 1.0;
        _context.drawImageScaledFromSource(img,
            _animateX, 0, imgWidth, height,
            x, y,
            imgWidth, height);
        if (_frameTime > 0.25) {
          _frameTime = 0.0;
          _animateX = _animateX + imgWidth;
          if (_animateX >= img.width) {
            _animateX = 0;
          }
        }
      }

      _context.restore();

      x+= imgWidth + betweenDistance;
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
    _context.fillText(
        text, _width / 2 - metrics.width / 2, y);
    _context.save();
  }

}