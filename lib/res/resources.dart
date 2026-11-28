import 'dart:async';

/// Common interface for P2P chunked resource stores ([ImageIndex], [Sounds]).
abstract class NetworkResourceStore {
  bool resourceIsLoaded(int index);
  bool resourceIsLoading(int index);
  String getResourceDataUrl(int index);
  bool verifyResourceDataHash(int index, String data);
  Future addFromResourceData(int index, String data, bool allowCaching);
  Future addSingleResourceByIndex(int index);
  String resourceNameFromIndex(int index);
  List<int> orderedResourceIds();
  void ensureIndexedForNetwork();
  void loadAllFromServer();
}
