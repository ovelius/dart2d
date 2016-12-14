library imageindex;

import 'dart:html';
import 'dart:math';
import 'dart:async';
import 'package:di/di.dart';

List<String> imageSources = [
    "shipg01.png",
    "shield.png",
    "shipr01.png",
    "shipb01.png",
    "shipy01.png",
    "fire.png",
    "astroid.png",
    "astroid2.png",
    "astroid3.png",
    "duck.png",
    "dragon.png",
    "world.png",
    "cake.png",
    "banana.png",
    "zooka.png",
    "box.png",
    "gun.png",
];


var _EMPTY_IMAGE = () {
  ImageElement img = new ImageElement(width:100, height:100);
  img.src = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUAAAAFCAYAAACNbyblAAAADElEQVQImWNgoBMAAABpAAFEI8ARAAAAAElFTkSuQmCC";
  return img;
};

@Injectable()
class ImageIndex {
  getImageByName(String name) {
    return imageByName[name];
  }
  getImageByIndex(int index) {
    return images[index];
  }
}
// Item 0 is always empty image.
List<ImageElement> images = [_EMPTY_IMAGE()];

List<Future> imageFutures = [];

// Map ImageName -> ImageId.
Map imageByName = new Map<String, int>();
Map loadedImages = new Map<String, bool>();

bool finishedLoadingImages() {
  return loadedImages.length == imageSources.length;
}

String imagesLoadedString() {
  return "${loadedImages.length}/${imageSources.length}";
}

Map<String, String> dataUrlCache_ = new Map();
/**
 * Return and an img.src represenation of this image.
 */
String getImageDataUrl(String name) {
  if (dataUrlCache_.containsKey(name)) {
    return dataUrlCache_[name];
  }
  int index = imageByName[name];
  ImageElement image = images[index];
  CanvasElement canvas = new CanvasElement(width:image.width, height:image.height);
  canvas.context2D.drawImage(image, 0, 0);
  String data = canvas.toDataUrl("image/png");
  dataUrlCache_[name] = data;
  return data;
}

void addFromImageData(String name, String data) {
  images[imageByName[name]].src = data;
  loadedImages[name] = true;
}

loadImagesFromNetwork() {
  for (var img in imageSources) {
    ImageElement element = new ImageElement();
    images.add(element);
    imageByName[img] = images.length - 1;
  }
}

useEmptyImagesForTest() {
  for (var img in imageSources) {
    images.add(_EMPTY_IMAGE());
    imageByName[img] = images.length - 1;
    loadedImages[img] = true;
  }
}

bool imagesIndexed() {
  return imageByName.length >= imageSources.length;
}

loadImagesFromServer([String path = "./img/"]) {
  // TODO: What if partially loaded from client? 
  // loadedImages[name] will be true then.
  for (var img in imageSources) {
    ImageElement element = new ImageElement(src: path + img);
    images.add(element);
    imageFutures.add(element.onLoad.first);
    element.onLoad.first.then((e) {
      loadedImages[img] = true;
    });
    imageByName[img] = images.length - 1;
  }
  return Future.wait(imageFutures);
}