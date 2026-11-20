package com.turboimage;

import androidx.annotation.Nullable;
import com.facebook.react.viewmanagers.TurboImageViewManagerDelegate;

/**
 * The Codegen delegate, plus the border style props it does not route (see
 * {@link TurboImageBorders}).
 *
 * <p>Java on purpose, the only Java file in the library. React Native
 * declares {@code ViewManagerDelegate.setProperty} twice, once for Kotlin and
 * once under the JVM name the generated Java delegate overrides. A Kotlin
 * subclass would override the Kotlin one and bypass the generated method; a
 * Java subclass overrides the same method the generated class does.
 */
final class TurboImagePropsDelegate
    extends TurboImageViewManagerDelegate<TurboImageView, TurboImageViewManager> {

  TurboImagePropsDelegate(TurboImageViewManager viewManager) {
    super(viewManager);
  }

  @Override
  public void setProperty(TurboImageView view, String propName, @Nullable Object value) {
    if (!TurboImageBorders.apply(view, propName, value)) {
      super.setProperty(view, propName, value);
    }
  }
}
