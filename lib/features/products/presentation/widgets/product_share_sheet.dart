import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/platform/file_share_support.dart' as platform;
import '../../domain/models/product_model.dart';
import '../../domain/models/product_share.dart';
import 'product_share_card.dart';

/// The product's own image, downloaded and ready to attach.
class ShareImageFile {
  const ShareImageFile({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
  });

  final Uint8List bytes;
  final String mimeType;
  final String fileName;
}

/// Platform actions used by the share sheet; replaceable in tests.
class ProductSharer {
  ProductSharer({
    Future<ShareImageFile> Function(ProductModel product)? fetchImage,
    this.canShareFile = _canShareFile,
    this.shareFile = _shareFile,
    this.downloader = platform.downloadBytes,
    this.launcher = _launchExternal,
    Future<ShareImageFile> Function(ProductModel product, ShareImageFile photo)?
    buildCard,
  }) : fetchImage = fetchImage ?? fetchProductImageFile,
       buildCard = buildCard ?? buildProductShareCardFile;

  /// Turns the product photo into the shared product card (image with name,
  /// SKU, category and MRP).
  final Future<ShareImageFile> Function(
    ProductModel product,
    ShareImageFile photo,
  )
  buildCard;

  /// Downloads the exact product image from the backend.
  final Future<ShareImageFile> Function(ProductModel product) fetchImage;

  /// `navigator.canShare({ files })` on the web; true on Android/iOS.
  final bool Function(ShareImageFile file) canShareFile;

  /// `navigator.share({ files, text })` on the web; the share sheet on
  /// Android/iOS. Returns 'shared', 'dismissed' or 'failed: <reason>'.
  final Future<String> Function(ShareImageFile file, String text) shareFile;

  final Future<bool> Function(List<int> bytes, String name, String mime)
  downloader;
  final Future<bool> Function(Uri uri) launcher;
}

bool _canShareFile(ShareImageFile f) =>
    platform.canShareImageFile(f.bytes, f.fileName, f.mimeType);

Future<String> _shareFile(ShareImageFile f, String text) =>
    platform.shareImageFile(f.bytes, f.fileName, f.mimeType, text);

Future<bool> _launchExternal(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// GET /share/products/<id>/image → a real image file (bytes + MIME type).
Future<ShareImageFile> fetchProductImageFile(ProductModel product) async {
  final response = await Dio().getUri<List<int>>(
    productImageFileUrl(product),
    options: Options(
      responseType: ResponseType.bytes,
      receiveTimeout: const Duration(seconds: 45),
    ),
  );
  final type = (response.headers.value('content-type') ?? '')
      .split(';')
      .first
      .trim()
      .toLowerCase();
  final bytes = Uint8List.fromList(response.data ?? const []);
  if (!type.startsWith('image/') || bytes.isEmpty) {
    throw StateError('The server did not return an image for this product.');
  }
  final ext = switch (type) {
    'image/png' => 'png',
    'image/webp' => 'webp',
    _ => 'jpg',
  };
  return ShareImageFile(
    bytes: bytes,
    mimeType: type,
    fileName: '${shareFileName(product)}.$ext',
  );
}

/// The WhatsApp product card for [product], built from its own [photo].
/// Shows MRP only (never the dealer or purchase price).
Future<ShareImageFile> buildProductShareCardFile(
  ProductModel product,
  ShareImageFile photo,
) async {
  final bytes = await renderProductShareCard(product, photo.bytes);
  return ShareImageFile(
    bytes: bytes,
    mimeType: 'image/png',
    fileName: '${shareFileName(product)}.png',
  );
}

/// Opens the share options. The product image is downloaded as soon as the
/// sheet opens, so tapping "Share on WhatsApp" can call `navigator.share`
/// immediately (browsers only allow it during the tap).
Future<void> showProductShareSheet(
  BuildContext context, {
  required ProductModel product,
  ProductSharer? sharer,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ProductShareSheet(
      product: product,
      sharer: sharer ?? ProductSharer(),
      hostContext: context,
    ),
  );
}

class _ProductShareSheet extends StatefulWidget {
  const _ProductShareSheet({
    required this.product,
    required this.sharer,
    required this.hostContext,
  });

  final ProductModel product;
  final ProductSharer sharer;
  final BuildContext hostContext;

  @override
  State<_ProductShareSheet> createState() => _ProductShareSheetState();
}

class _ProductShareSheetState extends State<_ProductShareSheet> {
  ShareImageFile? _image;
  Object? _error;
  bool _canAttach = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _image = null;
      _error = null;
    });
    try {
      // The product's own picture, then the card built from it.
      final photo = await widget.sharer.fetchImage(widget.product);
      final image = await widget.sharer.buildCard(widget.product, photo);
      if (!mounted) return;
      setState(() {
        _image = image;
        _canAttach = widget.sharer.canShareFile(image);
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _shareOnWhatsApp() {
    final image = _image;
    if (image == null) return;
    final host = widget.hostContext;
    if (_canAttach) {
      // Called directly from the tap: navigator.share needs the user gesture.
      // Only the card image is sent; its details are inside the image.
      final pending = widget.sharer.shareFile(image, '');
      Navigator.of(context).pop();
      pending.then((outcome) {
        if (outcome.startsWith('failed') && host.mounted) {
          _manualAttach(host, image, reason: outcome);
        }
      });
      return;
    }
    Navigator.of(context).pop();
    _manualAttach(host, image);
  }

  /// No file sharing here: download the product card and explain how to
  /// attach it in WhatsApp (its details are inside the image).
  Future<void> _manualAttach(
    BuildContext host,
    ShareImageFile image, {
    String? reason,
  }) async {
    final sharer = widget.sharer;
    final saved = await sharer.downloader(
      image.bytes,
      image.fileName,
      image.mimeType,
    );
    if (!host.mounted) return;
    await showDialog<void>(
      context: host,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('share-manual-attach'),
        title: const Text('Attach the product card in WhatsApp'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  image.bytes,
                  height: 140,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.image_outlined, size: 64),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              saved
                  ? 'This browser cannot attach files to WhatsApp directly. '
                        'The product card was downloaded as '
                        '"${image.fileName}". Its name, SKU, category and MRP '
                        'are inside the image.'
                  : 'This device cannot attach files to WhatsApp directly, '
                        'and the product card could not be downloaded here.',
            ),
            const SizedBox(height: 10),
            const Text(
              '1. Open WhatsApp and choose the chat.\n'
              '2. Attach the downloaded product card.\n'
              '3. Send.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            key: const ValueKey('share-open-whatsapp'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
            ),
            icon: const Icon(Icons.chat_rounded),
            label: const Text('Open WhatsApp'),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              sharer.launcher(Uri.parse('https://web.whatsapp.com/'));
            },
          ),
        ],
      ),
    );
  }

  Future<void> _download() async {
    final image = _image;
    if (image == null) return;
    final host = widget.hostContext;
    Navigator.of(context).pop();
    if (_canAttach) {
      final outcome = await widget.sharer.shareFile(image, '');
      if (outcome.startsWith('failed') && host.mounted) {
        _manualAttach(host, image, reason: outcome);
      }
      return;
    }
    final saved = await widget.sharer.downloader(
      image.bytes,
      image.fileName,
      image.mimeType,
    );
    if (host.mounted) {
      _snack(
        host,
        saved ? 'Saved ${image.fileName}' : 'Download is not available here.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = _image == null && _error == null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _image != null
                          ? Image.memory(
                              _image!.bytes,
                              key: const ValueKey('share-image-preview'),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.image_outlined),
                            )
                          : ColoredBox(
                              color: const Color(0xFFEFF4FA),
                              child: Center(
                                child: loading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.broken_image_outlined),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Share product',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          widget.product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null)
              ListTile(
                key: const ValueKey('share-image-error'),
                leading: const Icon(Icons.error_outline, color: Colors.red),
                title: const Text('Could not prepare the product card'),
                subtitle: Text('$_error', maxLines: 2),
                trailing: TextButton(
                  onPressed: _load,
                  child: const Text('Retry'),
                ),
              ),
            ListTile(
              key: const ValueKey('share-whatsapp'),
              enabled: _image != null,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF25D366),
                foregroundColor: Colors.white,
                child: Icon(Icons.chat_rounded),
              ),
              title: const Text('Share on WhatsApp'),
              subtitle: Text(
                loading
                    ? 'Preparing product card…'
                    : _image == null
                    ? 'Product card unavailable'
                    : _canAttach
                    ? 'Sends one image with the product photo, name, SKU, category and MRP'
                    : 'Downloads the product card to attach in WhatsApp',
              ),
              onTap: _shareOnWhatsApp,
            ),
            ListTile(
              key: const ValueKey('share-image'),
              enabled: _image != null,
              leading: const CircleAvatar(child: Icon(Icons.image_outlined)),
              title: Text(
                _canAttach ? 'Share to other apps' : 'Download product card',
              ),
              onTap: _download,
            ),
            ListTile(
              key: const ValueKey('share-copy-link'),
              leading: const CircleAvatar(child: Icon(Icons.link_rounded)),
              title: const Text('Copy product link'),
              onTap: () async {
                final host = widget.hostContext;
                Navigator.of(context).pop();
                await Clipboard.setData(
                  ClipboardData(
                    text: productShareUrl(widget.product).toString(),
                  ),
                );
                if (host.mounted) _snack(host, 'Product link copied');
              },
            ),
          ],
        ),
      ),
    );
  }
}

String shareFileName(ProductModel product) {
  final base = (product.sku.trim().isNotEmpty ? product.sku : product.name)
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-');
  return base.isEmpty ? 'product' : base;
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
