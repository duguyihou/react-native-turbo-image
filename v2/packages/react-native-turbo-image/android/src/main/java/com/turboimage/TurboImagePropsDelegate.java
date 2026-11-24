package com.turboimage;

import androidx.annotation.Nullable;
import com.facebook.react.viewmanagers.TurboImageViewManagerDelegate;

/**
 * The Codegen delegate plus the border props it does not route.
 *
 * <p>Java on purpose: a Kotlin override of {@code setProperty} would bind to a
 * different JVM method than the generated Java delegate and bypass it.
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
