import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Result of a file share: 'shared', 'dismissed' or 'failed: <reason>'.
typedef FileShareOutcome = String;

web.File _file(Uint8List bytes, String fileName, String mimeType) => web.File(
  <JSAny>[bytes.toJS].toJS,
  fileName,
  web.FilePropertyBag(type: mimeType),
);

/// `navigator.canShare({ files: [imageFile] })` with the actual image file.
bool canShareImageFile(Uint8List bytes, String fileName, String mimeType) {
  try {
    final navigator = web.window.navigator;
    if (!navigator.has('share') || !navigator.has('canShare')) return false;
    return navigator.canShare(
      web.ShareData(files: <web.File>[_file(bytes, fileName, mimeType)].toJS),
    );
  } catch (_) {
    return false;
  }
}

/// `navigator.share({ files: [imageFile], text })`: opens the device share
/// sheet (pick WhatsApp) with the image attached and the details as caption.
///
/// Browsers only allow this during a user gesture, so callers must call it
/// straight from the tap handler, with the image already downloaded.
Future<FileShareOutcome> shareImageFile(
  Uint8List bytes,
  String fileName,
  String mimeType,
  String text, {
  String? title,
}) async {
  try {
    // ONE share payload: the image file, the message text and the title.
    final files = <web.File>[_file(bytes, fileName, mimeType)].toJS;
    final hasTitle = title != null && title.trim().isNotEmpty;
    await web.window.navigator
        .share(
          text.isEmpty
              ? (hasTitle
                    ? web.ShareData(files: files, title: title)
                    : web.ShareData(files: files))
              : (hasTitle
                    ? web.ShareData(files: files, text: text, title: title)
                    : web.ShareData(files: files, text: text)),
        )
        .toDart;
    return 'shared';
  } catch (error) {
    final message = '$error';
    if (message.contains('AbortError')) return 'dismissed';
    return 'failed: $message';
  }
}

/// Whether WhatsApp keeps the text shared together with an image: true on
/// phones (it becomes the caption, "Add a message"); false in desktop
/// browsers, where the share goes to WhatsApp Desktop, which takes only the
/// image.
bool whatsAppKeepsSharedText() {
  final agent = web.window.navigator.userAgent.toLowerCase();
  return RegExp(r'android|iphone|ipad|ipod|mobile').hasMatch(agent);
}

/// Saves the bytes with the browser's download prompt, so the image can be
/// attached in WhatsApp Web / Desktop by hand.
Future<bool> downloadBytes(
  List<int> bytes,
  String fileName,
  String mimeType,
) async {
  try {
    final blob = web.Blob(
      <JSAny>[Uint8List.fromList(bytes).toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..style.display = 'none';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    Future<void>.delayed(
      const Duration(seconds: 30),
      () => web.URL.revokeObjectURL(url),
    );
    return true;
  } catch (_) {
    return false;
  }
}
