import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Result of a file share: 'shared', 'dismissed' or 'failed: <reason>'.
typedef FileShareOutcome = String;

/// Android and iOS share sheets accept image files (WhatsApp included).
bool canShareImageFile(Uint8List bytes, String fileName, String mimeType) =>
    Platform.isAndroid || Platform.isIOS;

/// Android / iOS: WhatsApp keeps the shared text as the image caption.
bool whatsAppKeepsSharedText() => Platform.isAndroid || Platform.isIOS;

/// Opens the system share sheet with the image file and its caption.
Future<FileShareOutcome> shareImageFile(
  Uint8List bytes,
  String fileName,
  String mimeType,
  String text, {
  String? title,
}) async {
  try {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: mimeType, name: fileName)],
        fileNameOverrides: [fileName],
        // ONE share: the image with the details as its caption.
        text: text.isEmpty ? null : text,
        subject: title,
      ),
    );
    switch (result.status) {
      case ShareResultStatus.success:
        return 'shared';
      case ShareResultStatus.dismissed:
        return 'dismissed';
      case ShareResultStatus.unavailable:
        return 'failed: unavailable';
    }
  } catch (error) {
    return 'failed: $error';
  }
}

/// Saves bytes as a download. Only available on the web.
Future<bool> downloadBytes(
  List<int> bytes,
  String fileName,
  String mimeType,
) async => false;
