package com.turboimage

import com.facebook.react.uimanager.ThemedReactContext

class TurboImageViewManager : TurboImageViewManagerBase<TurboImageView>() {
  override fun getName() = REACT_CLASS

  override fun getImageView(reactContext: ThemedReactContext): TurboImageView {
    return TurboImageView(reactContext)
  }

  companion object {
    private const val REACT_CLASS = "TurboImageView"
  }
}
