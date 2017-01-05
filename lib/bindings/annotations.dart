import 'package:di/di.dart';

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

@Injectable()
class PacketListenerBindings {
  Map<String, dynamic> _handlers;

  bindHandler(String key, dynamic handler) {
    _handlers[key] = handler;
  }

  handlerFor(String key) {
    assert (_handlers.containsKey(key));
    return _handlers[key];
  }
}
