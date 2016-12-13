class WorldWidth {
  const WorldWidth();
}

class WorldHeight {
  const WorldHeight();
}

class WorldCanvas {
  const WorldCanvas();
}

class ByteWorldCanvas {
  const ByteWorldCanvas();
}

class CanvasMarker {
  int width;
  int height;

  var context2D;
}

class PeerMarker { }

class CanvasFactory {
  CanvasFactory(this._factory);
  dynamic _factory;
  CanvasMarker createCanvas(int width, int height) {
    return _factory(width, height);
  }
}
