import Foundation

/// Tracks cache identity keys (cacheKey ?? uri) ever used by TurboImage, since
/// Nuke's DataCache/ImageCache expose no enumerate API — prefix-based clearing
/// needs its own index to know which keys exist.
final class TurboImageCacheKeyIndex {
  static let shared = TurboImageCacheKeyIndex()

  private let defaultsKey = "TurboImageCacheKeyIndex"
  private let queue = DispatchQueue(label: "com.turboimage.cacheKeyIndex")
  private let defaults = UserDefaults.standard

  private init() {}

  func register(_ key: String) {
    queue.sync {
      var keys = storedKeys()
      if keys.insert(key).inserted {
        defaults.set(Array(keys), forKey: defaultsKey)
      }
    }
  }

  func keys(includePrefix: String?, excludePrefix: String?) -> [String] {
    queue.sync {
      storedKeys().filter { key in
        let included = includePrefix.map { key.hasPrefix($0) } ?? true
        let excluded = excludePrefix.map { key.hasPrefix($0) } ?? false
        return included && !excluded
      }
    }
  }

  func remove(_ keys: [String]) {
    queue.sync {
      var stored = storedKeys()
      keys.forEach { stored.remove($0) }
      defaults.set(Array(stored), forKey: defaultsKey)
    }
  }

  func removeAll() {
    queue.sync {
      defaults.removeObject(forKey: defaultsKey)
    }
  }

  private func storedKeys() -> Set<String> {
    Set(defaults.stringArray(forKey: defaultsKey) ?? [])
  }
}
