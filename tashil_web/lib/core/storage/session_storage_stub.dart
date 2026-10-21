final Map<String, String> _memoryStore = <String, String>{};

String? platformStorageGet(String key) => _memoryStore[key];

void platformStorageSet(String key, String value) {
  _memoryStore[key] = value;
}

void platformStorageRemove(String key) {
  _memoryStore.remove(key);
}

void platformStorageClear() {
  _memoryStore.clear();
}

void platformUpdateUrl(String path) {}
