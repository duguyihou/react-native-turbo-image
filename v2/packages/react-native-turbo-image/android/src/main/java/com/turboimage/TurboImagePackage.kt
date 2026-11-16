package com.turboimage

import com.facebook.react.ReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.uimanager.ViewManager

class TurboImagePackage : ReactPackage {
  override fun createViewManagers(reactContext: ReactApplicationContext): List<ViewManager<*, *>> =
    listOf(TurboImageViewManager())

  // TODO: the prefetch/cache-management TurboModule lands with the pipeline
  // milestone; until then the package registers no native modules.
  @Deprecated("Deprecated in ReactPackage; kept only because it is abstract.")
  override fun createNativeModules(reactContext: ReactApplicationContext): List<NativeModule> =
    emptyList()
}
