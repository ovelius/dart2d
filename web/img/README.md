# Images (`web/img/`)

Whenever you add, remove, or modify any image in this directory, remember to regenerate the image CRC32 hashes:

```sh
dart run tool/generate_image_hashes.dart
```

This updates `lib/res/image_hashes.dart`, which is used for resource integrity and caching.
