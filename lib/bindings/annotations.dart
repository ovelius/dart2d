class WorldWidth {
  const WorldWidth();
}

class WorldHeight {
  const WorldHeight();
}

class WorldCanvas {
  const WorldCanvas();
}

class CanvasFactory {
  const CanvasFactory();
}

class ImageFactory {
  const ImageFactory();
}

class ByteWorldCanvas {
  const ByteWorldCanvas();
}

class PeerMarker {
  const PeerMarker();
}

class DynamicFactory {
  DynamicFactory(this._factory);
  dynamic _factory;
  create(var args) {
    return _factory(args);
  }
}
