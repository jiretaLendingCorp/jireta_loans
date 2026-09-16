// lib/presentation/shared/widgets/details/collection_proof_viewer.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// One viewable collection proof (photo/signature).
class CollectionProofItem {
  final String label;
  final String url;
  const CollectionProofItem({required this.label, required this.url});
}

/// Opens a dialog showing the rider's submitted proofs.
/// [title] defaults to 'Collection Proof' (collections flow); pass
/// 'Cash on Delivery Proof' for disbursement proofs.
Future<void> showCollectionProofDialog(
  BuildContext context,
  List<CollectionProofItem> items, {
  String title = 'Collection Proof',
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
              child: Row(
                children: [
                  const Icon(Icons.photo_library_outlined,
                      color: AppColors.deepNavy, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close,
                        size: 20, color: AppColors.textSecondary),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final item in items)
                      _ProofTile(label: item.label, url: item.url),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Fullscreen na viewer ng proof — direktang bukas ito (walang maliit na
/// dialog sa pagitan). Pwedeng mag-swipe sa pagitan ng proofs kung higit isa.
Future<void> showCollectionProofFullscreen(
  BuildContext context,
  List<CollectionProofItem> items, {
  int initialIndex = 0,
}) {
  if (items.isEmpty) return Future<void>.value();
  final index = initialIndex < 0
      ? 0
      : (initialIndex >= items.length ? items.length - 1 : initialIndex);
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    builder: (_) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: _ProofFullscreenViewer(items: items, initialIndex: index),
    ),
  );
}

/// PageView + caption + close button ng [showCollectionProofFullscreen].
class _ProofFullscreenViewer extends StatefulWidget {
  final List<CollectionProofItem> items;
  final int initialIndex;
  const _ProofFullscreenViewer(
      {required this.items, required this.initialIndex});

  @override
  State<_ProofFullscreenViewer> createState() => _ProofFullscreenViewerState();
}

class _ProofFullscreenViewerState extends State<_ProofFullscreenViewer> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  /// Sariling transform ng kasalukuyang larawan — dito rin sinusukat kung
  /// naka-zoom para hindi makipag-agawan ang PageView sa pan gesture.
  final _transform = TransformationController();
  bool _zoomed = false;

  static const _zoomedThreshold = 1.01;

  bool get _isZoomed => _transform.value.getMaxScaleOnAxis() > _zoomedThreshold;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransformChanged);
  }

  void _onTransformChanged() {
    if (_isZoomed != _zoomed) setState(() => _zoomed = _isZoomed);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransformChanged);
    _transform.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    return Stack(
      children: [
        PageView.builder(
          controller: _controller,
          // Habang naka-zoom, sarado ang page swipe. Dati ay bukas ito at
          // nananalo ang PageView sa horizontal drag (18px drag slop vs 36px
          // pan slop ng InteractiveViewer), kaya imbis na mag-pan ang naka-zoom
          // na larawan ay dumudulas ito palipat-lipat ng page — parang maling
          // direksyon ang galaw. Kapag sarado ang physics, wala nang drag
          // recognizer ang PageView at ang InteractiveViewer na ang humahawak
          // sa pan.
          physics: _zoomed
              ? const NeverScrollableScrollPhysics()
              : const PageScrollPhysics(),
          itemCount: widget.items.length,
          onPageChanged: (i) {
            // Bagong larawan → balik sa fit at naka-center.
            _transform.value = Matrix4.identity();
            setState(() {
              _index = i;
              _zoomed = false;
            });
          },
          itemBuilder: (_, i) => InteractiveViewer(
            // Isang controller lang para sa aktibong page.
            transformationController: i == _index ? _transform : null,
            minScale: 1,
            maxScale: 5,
            // Wheel/trackpad = zoom (desktop), drag = pan kapag naka-zoom.
            trackpadScrollCausesScale: true,
            child: SizedBox.expand(
              // Ang child ay eksaktong laki ng viewport (letterboxed ang
              // larawan sa loob), kaya nananatiling naka-center ang larawan
              // habang nag-zoom at hindi ito gumagalaw sa sarili nitong
              // direksyon.
              child: Center(
                child: Image.network(
                  widget.items[i].url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      size: 60,
                      color: Colors.white24),
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.items.length > 1
                    ? '${item.label}  •  ${_index + 1}/${widget.items.length}'
                    : item.label,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: IconButton.filledTonal(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProofTile extends StatelessWidget {
  final String label;
  final String url;
  const _ProofTile({required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _openFullscreen(context),
          child: Container(
            width: 224,
            height: 224,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
              color: AppColors.surfaceVariant,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(url,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, progress) =>
                          progress == null
                              ? child
                              : const Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image_outlined,
                          size: 40,
                          color: AppColors.textTertiary)),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.zoom_in,
                          size: 14, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }

  void _openFullscreen(BuildContext context) => showCollectionProofFullscreen(
        context,
        [CollectionProofItem(label: label, url: url)],
      );
}
