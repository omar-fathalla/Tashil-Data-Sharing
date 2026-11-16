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

void platformReplaceUrl(String path) {}

String platformCurrentPath() => '';

final Map<String, String> _memoryQuery = <String, String>{};

String? platformQueryParam(String name) => _memoryQuery[name];

void platformReplaceQueryParam(String name, String? value) {
  if (value == null || value.isEmpty) {
    _memoryQuery.remove(name);
  } else {
    _memoryQuery[name] = value;
  }
}
