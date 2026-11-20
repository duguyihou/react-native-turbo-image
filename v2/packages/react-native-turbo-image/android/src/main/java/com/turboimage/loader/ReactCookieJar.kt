package com.turboimage.loader

import com.facebook.react.modules.network.ForwardingCookieHandler
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl

/**
 * Sends and stores cookies through React Native's cookie store, so an image
 * request carries the session that the app's `fetch` (or a WebView)
 * established. iOS gets the same from `URLSessionConfiguration.default`,
 * which uses the shared `HTTPCookieStorage`.
 *
 * This is the only host state the adapter's client takes on. It does not use
 * React Native's `OkHttpClient`, whose interceptors would change how images
 * load with every app (RFC §4.2).
 *
 * `ForwardingCookieHandler` is the handler React Native's own networking
 * installs; it forwards to the platform `CookieManager`. OkHttp's
 * `JavaNetCookieJar` would adapt it too, but that class lives in a separate
 * artifact (`okhttp-urlconnection`, renamed and moved to another package in
 * OkHttp 5) that this library would reach only through React Native's
 * dependencies. The adaptation is small enough to own.
 */
internal class ReactCookieJar : CookieJar {
  // Creating the handler is cheap; it resolves the platform `CookieManager`
  // on first use, which happens here on an OkHttp thread. On a device without
  // a WebView implementation it reports no cookies instead of failing.
  private val handler = ForwardingCookieHandler()

  override fun loadForRequest(url: HttpUrl): List<Cookie> {
    val headers =
      try {
        handler.get(url.toUri(), emptyMap())
      } catch (e: Exception) {
        // A cookie store that cannot be read must not fail the image load.
        return emptyList()
      }
    // The store answers with one `Cookie` request header: "a=1; b=2". It has
    // already matched domain, path, expiry and `Secure` against the URL, so
    // each pair only needs wrapping; OkHttp writes back name and value alone.
    return headers
      .filterKeys { it.equals("Cookie", ignoreCase = true) }
      .values
      .flatten()
      .flatMap { it.split(';') }
      .mapNotNull { pair ->
        val name = pair.substringBefore('=', missingDelimiterValue = "").trim()
        val value = pair.substringAfter('=', missingDelimiterValue = "").trim()
        // `Cookie.Builder` throws on names and values OkHttp could not send
        // (empty name, control characters). Skip those and keep the rest.
        runCatching { Cookie.Builder().name(name).value(value).domain(url.host).build() }.getOrNull()
      }
  }

  override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
    if (cookies.isEmpty()) return
    try {
      // `Cookie.toString()` is the `Set-Cookie` form, attributes included.
      handler.put(url.toUri(), mapOf("Set-Cookie" to cookies.map { it.toString() }))
    } catch (e: Exception) {
      // As above: losing a cookie is better than losing the image.
    }
  }
}
