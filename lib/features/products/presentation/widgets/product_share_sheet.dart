import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/platform/file_share_support.dart' as platform;
import '../../domain/category_price_view.dart';
import '../../domain/models/product_model.dart';
import '../../domain/models/product_share.dart';
import 'product_share_card.dart';
import '../../../../core/widgets/app_toast.dart';

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
    this.textReachesWhatsApp = platform.whatsAppKeepsSharedText,
    Future<ShareImageFile> Function(
      ProductModel product,
      ShareImageFile? photo,
      ProductPriceView view,
    )?
    buildCard,
  }) : fetchImage = fetchImage ?? fetchProductImageFile,
       buildCard = buildCard ?? buildProductShareCardFile;

  /// Turns the product photo into the shared product card (image with name,
  /// SKU, category and the share price for [ProductPriceView]). A null photo
  /// (the image could not be loaded) gives the water-drop placeholder card.
  final Future<ShareImageFile> Function(
    ProductModel product,
    ShareImageFile? photo,
    ProductPriceView view,
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

  /// Whether WhatsApp keeps the text shared with the image (phones: yes, it
  /// becomes the caption; WhatsApp Desktop: no, it takes only the image).
  final bool Function() textReachesWhatsApp;
}

bool _canShareFile(ShareImageFile f) =>
    platform.canShareImageFile(f.bytes, f.fileName, f.mimeType);

/// One share: image file + message text (+ the product name as title,
/// taken from the message's first line "Product Name: ...").
Future<String> _shareFile(ShareImageFile f, String text) {
  final first = text.split('\n').first;
  const prefix = 'Product Name: ';
  return platform.shareImageFile(
    f.bytes,
    f.fileName,
    f.mimeType,
    text,
    title: first.startsWith(prefix) ? first.substring(prefix.length) : null,
  );
}

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

/// The WhatsApp product card for [product], built from its own [photo]
/// (null: water-drop placeholder). One price: MRP, or the Cabinet Price when
/// shared from the Cabinet page (never the dealer or purchase price).
Future<ShareImageFile> buildProductShareCardFile(
  ProductModel product,
  ShareImageFile? photo, [
  ProductPriceView view = ProductPriceView.standard,
]) async {
  final bytes = await renderProductShareCard(
    product,
    photo?.bytes,
    view: view,
  );
  return ShareImageFile(
    bytes: bytes,
    mimeType: 'image/png',
    fileName: '${shareFileName(product)}.png',
  );
}

/// Product cards built ahead (when the Product Details page opens), so one
/// tap on Share can call `navigator.share` straight away: browsers allow it
/// only right after the tap, and fetching + drawing the card takes longer.
class ProductShareCards {
  ProductShareCards._();

  static final _pending = <String, Future<ShareImageFile>>{};
  static final _ready = <String, ShareImageFile>{};

  /// Changes whenever what the card shows changes (including the page it is
  /// shared from, which decides its price).
  static String _key(ProductModel p, ProductPriceView view) => [
    p.id,
    p.name,
    p.sku,
    p.mrp,
    p.cabinetPrice,
    p.categoryName,
    p.imageUrl,
    view.name,
  ].join('|');

  /// Builds (once) the card for [product] shared from [view]. If the
  /// product's image cannot be loaded, the card uses the water-drop
  /// placeholder, so an image failure never blocks sharing.
  static Future<ShareImageFile> prepare(
    ProductModel product,
    ProductSharer sharer, {
    ProductPriceView view = ProductPriceView.standard,
  }) {
    final key = _key(product, view);
    return _pending.putIfAbsent(key, () async {
      try {
        ShareImageFile? photo;
        try {
          photo = await sharer.fetchImage(product);
        } catch (_) {
          photo = null; // saved image unavailable: placeholder card
        }
        final card = await sharer.buildCard(product, photo, view);
        _ready[key] = card;
        return card;
      } catch (_) {
        _pending.remove(key); // allow a retry
        rethrow;
      }
    });
  }

  /// The finished card, or null while it is still being built.
  static ShareImageFile? ready(
    ProductModel product, {
    ProductPriceView view = ProductPriceView.standard,
  }) => _ready[_key(product, view)];

  @visibleForTesting
  static void clear() {
    _pending.clear();
    _ready.clear();
  }
}

/// The Share icon: ONE tap, ONE `navigator.share` with the product image
/// (files), every product detail (text) and the product name (title).
/// If the card is still being built, the share sheet opens and its "Share on
/// WhatsApp" does the same single share as soon as the card is ready.
Future<void> shareProductInOneClick(
  BuildContext context, {
  required ProductModel product,
  ProductSharer? sharer,
  ProductPriceView view = ProductPriceView.standard,
}) async {
  final s = sharer ?? ProductSharer();
  final card = ProductShareCards.ready(product, view: view);
  if (card == null) {
    return showProductShareSheet(
      context,
      product: product,
      sharer: s,
      view: view,
    );
  }
  shareProductCard(context, product: product, card: card, sharer: s, view: view);
}

/// Shares [card] with the full details as its caption, in one share. Must be
/// called straight from a tap.
void shareProductCard(
  BuildContext host, {
  required ProductModel product,
  required ShareImageFile card,
  required ProductSharer sharer,
  ProductPriceView view = ProductPriceView.standard,
}) {
  final details = whatsAppShareText(product, view: view);
  if (!sharer.canShareFile(card)) {
    // No image + text sharing in this browser: say so, keep both.
    Clipboard.setData(ClipboardData(text: details)).catchError((_) {});
    showShareCompatibilityFallback(
      host,
      product: product,
      card: card,
      sharer: sharer,
      view: view,
    );
    return;
  }
  final keepsText = sharer.textReachesWhatsApp();
  if (!keepsText) {
    // WhatsApp Desktop takes the image but drops text shared with it: the
    // details are copied now (allowed only during the tap) for Ctrl+V.
    Clipboard.setData(ClipboardData(text: details)).catchError((_) {});
  }
  sharer.shareFile(card, details).then((outcome) {
    if (!host.mounted) return;
    if (outcome.startsWith('failed')) {
      Clipboard.setData(ClipboardData(text: details)).catchError((_) {});
      showShareCompatibilityFallback(
        host,
        product: product,
        card: card,
        sharer: sharer,
        reason: outcome,
        view: view,
      );
    } else if (outcome == 'shared' && !keepsText) {
      AppToast.success(
        host,
        'If WhatsApp Desktop left "Add a message" empty, press Ctrl+V: the '
        'product details are copied.',
      );
    }
  });
}

/// This browser cannot share the image together with the text: the image
/// is downloaded and the details copied, so the customer can attach the
/// image in WhatsApp and paste the details as its caption (one message).
Future<void> showShareCompatibilityFallback(
  BuildContext host, {
  required ProductModel product,
  required ShareImageFile card,
  required ProductSharer sharer,
  String? reason,
  ProductPriceView view = ProductPriceView.standard,
}) async {
  final saved = await sharer.downloader(
    card.bytes,
    card.fileName,
    card.mimeType,
  );
  if (!host.mounted) return;
  await showDialog<void>(
    context: host,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('share-manual-attach'),
      title: const Text('Share in WhatsApp'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  card.bytes,
                  height: 140,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.image_outlined, size: 64),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              saved
                  ? 'This browser cannot share an image together with text. '
                        'The product image was downloaded as '
                        '"${card.fileName}" and the full product details are '
                        'copied.'
                  : 'This browser cannot share an image together with text, '
                        'and the image could not be downloaded here. The full '
                        'product details are copied.',
            ),
            const SizedBox(height: 10),
            const Text(
              'In WhatsApp: choose the chat, attach the product image, paste '
              'the details (Ctrl+V) as its caption and send: one message.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
        OutlinedButton.icon(
          key: const ValueKey('share-whatsapp-text'),
          icon: const Icon(Icons.notes_rounded),
          label: const Text('Details only (text)'),
          onPressed: () {
            Navigator.of(dialogContext).pop();
            sharer.launcher(whatsAppShareUri(product, view: view));
          },
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

/// Opens the share options. The product image is downloaded as soon as the
/// sheet opens, so tapping "Share on WhatsApp" can call `navigator.share`
/// immediately (browsers only allow it during the tap).
Future<void> showProductShareSheet(
  BuildContext context, {
  required ProductModel product,
  ProductSharer? sharer,
  ProductPriceView view = ProductPriceView.standard,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ProductShareSheet(
      product: product,
      sharer: sharer ?? ProductSharer(),
      hostContext: context,
      view: view,
    ),
  );
}

class _ProductShareSheet extends StatefulWidget {
  const _ProductShareSheet({
    required this.product,
    required this.sharer,
    required this.hostContext,
    this.view = ProductPriceView.standard,
  });

  final ProductModel product;
  final ProductSharer sharer;
  final BuildContext hostContext;

  /// The page the product is shared from (decides its category and price).
  final ProductPriceView view;

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
      final image = await ProductShareCards.prepare(
        widget.product,
        widget.sharer,
        view: widget.view,
      );
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
    // Straight from the tap: ONE share with the image and every detail.
    shareProductCard(
      widget.hostContext,
      product: widget.product,
      card: image,
      sharer: widget.sharer,
      view: widget.view,
    );
    Navigator.of(context).pop();
  }

  Future<void> _download() async {
    final image = _image;
    if (image == null) return;
    final host = widget.hostContext;
    Navigator.of(context).pop();
    if (_canAttach) {
      final outcome = await widget.sharer.shareFile(image, '');
      if (outcome.startsWith('failed') && host.mounted) {
        showShareCompatibilityFallback(
          host,
          product: widget.product,
          card: image,
          sharer: widget.sharer,
          reason: outcome,
          view: widget.view,
        );
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
                    ? 'One message: the product image with all details'
                    : 'This browser cannot share an image with text',
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
              key: const ValueKey('share-copy-details'),
              leading: const CircleAvatar(child: Icon(Icons.copy_rounded)),
              title: const Text('Copy product details'),
              onTap: () async {
                final host = widget.hostContext;
                Navigator.of(context).pop();
                // The same message as the share (no product link).
                await Clipboard.setData(
                  ClipboardData(
                    text: whatsAppShareText(widget.product, view: widget.view),
                  ),
                );
                if (host.mounted) _snack(host, 'Product details copied');
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
  final failed = RegExp(
    r"could not|couldn't|failed|unable|error",
    caseSensitive: false,
  ).hasMatch(message);
  failed
      ? AppToast.error(context, message)
      : AppToast.success(context, message);
}
