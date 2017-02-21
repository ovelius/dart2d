class WorldWidth {
  const WorldWidth();
}

class WorldHeight {
  const WorldHeight();
}

class WorldCanvas {
  const WorldCanvas();
}

class LocalStorage {
  const LocalStorage();
}

class HtmlScreen {
  const HtmlScreen();
}

class TouchControls {
  const TouchControls();
}

class ServerFrameCounter {
  const ServerFrameCounter();
}

class LocalKeyState {
  const LocalKeyState();
}

class CanvasFactory {
  const CanvasFactory();
}

class ImageDataFactory {
  const ImageDataFactory();
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

/**
 * A generic factory object.
 * We use this to create fake HTML elements in testing.
 */
class DynamicFactory {
  DynamicFactory(this._factory);
  dynamic _factory;
  create(var args) {
    return _factory(args);
  }
}
