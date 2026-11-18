/// Sharing an image file together with text (so the actual product image is
/// attached in WhatsApp), plus a download fallback.
library;

export 'file_share_support_stub.dart'
    if (dart.library.js_interop) 'file_share_support_web.dart';
