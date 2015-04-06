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
    "manhattan2.png",
    "cake.png",
    "banana.png",
    "zooka.png",
];  

var _EMPTY_IMAGE = new CanvasElement(width:100, height:100);

var images = [_EMPTY_IMAGE];

var imageFutures = [];

var imageByName = new Map<String, int>();

useEmptyImagesForTest() {
  for (var img in imageSources) {
    images.add(_EMPTY_IMAGE);
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