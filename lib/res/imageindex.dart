library imageindex;

import 'dart:html';
import 'dart:async';

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
    "mattehorn.png",
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
// Item 0 is always empty image.
List<ImageElement> images = [_EMPTY_IMAGE()];

var imageFutures = [];

var imageByName = new Map<String, int>();

/**
 * Return and an img.src represenation of this image.
 */
String getImageDataUrl(String name) {
  int index = imageByName[name];
  ImageElement image = images[index];
  CanvasElement canvas = new CanvasElement(width:image.width, height:image.height);
  canvas.context2D.drawImage(image, 0, 0);
  return canvas.toDataUrl("image/png");
}

useEmptyImagesForTest() {
  for (var img in imageSources) {
    images.add(_EMPTY_IMAGE());
    imageByName[img] = images.length - 1;
  }
}

loadImages([String path = "./img/"]) {
  for (var img in imageSources) {
    ImageElement element = new ImageElement(src: path + img);
    images.add(element);
    imageFutures.add(element.onLoad.first);
    imageByName[img] = images.length - 1;
  }
  return Future.wait(imageFutures);
}