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

class ReloadFactory {
  const ReloadFactory();
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

abstract class GaReporter {
  reportEvent(String action, [String category, int count, String label]);
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
