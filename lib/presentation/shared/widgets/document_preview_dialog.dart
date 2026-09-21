// lib/presentation/shared/widgets/document_preview_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import 'document_viewer.dart';
import 'pdf_zoom_viewer.dart';

/// Isang pahina ng preview (hal. "Front Side" / "Back Side").
class DocumentPreviewPage {
  const DocumentPreviewPage({
    required this.label,
    required this.url,
    this.autoLandscape = false,
  });

  final String label;
  final String url;

  /// Para sa mga ID: awtomatikong i-rotate sa landscape kapag portrait ang
  /// litrato (tingnan ang `DocumentViewer.autoLandscape`).
  final bool autoLandscape;
}

/// Preview ng mga dokumento bilang **carousel** — ISA lang ang nakikita sa isang
/// pagkakataon, hindi na magkatabi (dati kasing Front at Back side by side, maliit
/// at mahirap tingnan).
///
/// Paraan ng paglipat:
/// * **Arrows** sa gilid (disabled kapag nasa dulo na)
/// * **Swipe** pakanan/pakaliwa (PageView)
/// * **Arrow keys** ng keyboard (← →) kapag naka-focus ang dialog
/// * **Dots** sa ilalim para sa mabilisang paglipat at bilang indicator
///
/// Bawat dokumento ay pwedeng **i-rotate 90°** (⟳) at i-zoom (+/−) — galing sa
/// `DocumentViewer`.
Future<void> showDocumentPreviewDialog(
  BuildContext context, {
  required String title,
  required List<DocumentPreviewPage> pages,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DocumentPreviewDialog(title: title, pages: pages),
  );
}

class _DocumentPreviewDialog extends StatefulWidget {
  const _DocumentPreviewDialog({required this.title, required this.pages});

  final String title;
  final List<DocumentPreviewPage> pages;

  @override
  State<_DocumentPreviewDialog> createState() => _DocumentPreviewDialogState();
}

class _DocumentPreviewDialogState extends State<_DocumentPreviewDialog> {
  final PageController _controller = PageController();
  int _index = 0;

  /// Kanya-kanyang manual rotation ang bawat pahina (0–3 quarter turns).
  final Map<int, int> _rotations = {};

  /// Kanya-kanyang zoom controller — para ang − / + sa toolbar ang mag-zoom ng
  /// kasalukuyang dokumento (katulad ng Ctrl+wheel at pinch).
  final Map<int, ZoomPaneController> _zoomControllers = {};

  @override
  void dispose() {
    for (final controller in _zoomControllers.values) {
      controller.removeListener(_onZoomChanged);
      controller.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  void _onZoomChanged() {
    if (mounted) setState(() {});
  }

  ZoomPaneController _zoomControllerFor(int index) =>
      _zoomControllers.putIfAbsent(index, () {
        final controller = ZoomPaneController();
        controller.addListener(_onZoomChanged);
        return controller;
      });

  /// Iikot ang kasalukuyang dokumento nang 90° (clockwise).
  void _rotateCurrent() {
    setState(() {
      _rotations[_index] = ((_rotations[_index] ?? 0) + 1) % 4;
    });
  }

  bool get _hasMultiple => widget.pages.length > 1;

  void _goTo(int index) {
    if (index < 0 || index >= widget.pages.length) return;
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.pages.isEmpty ? null : widget.pages[_index];
    return Dialog(
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                _goTo(_index - 1),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                _goTo(_index + 1),
          },
          child: Focus(
            autofocus: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                  child: Row(
                    children: [
                      if (page != null)
                        Expanded(
                          child: Text(
                            page.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      if (_hasMultiple)
                        Text(
                          '${_index + 1} / ${widget.pages.length}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      // − / + / ⟳ sa tabi mismo ng counter — hindi nakapatong sa
                      // dokumento.
                      _toolButton(
                        icon: Icons.remove_rounded,
                        tooltip: 'Zoom out',
                        enabled: _currentZoom.canZoomOut,
                        onTap: _currentZoom.zoomOut,
                      ),
                      _toolButton(
                        icon: Icons.add_rounded,
                        tooltip: 'Zoom in (Ctrl + wheel)',
                        enabled: _currentZoom.canZoomIn,
                        onTap: _currentZoom.zoomIn,
                      ),
                      _toolButton(
                        icon: Icons.rotate_right_rounded,
                        tooltip: 'Rotate 90°',
                        enabled: true,
                        onTap: _rotateCurrent,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: PageView.builder(
                          controller: _controller,
                          itemCount: widget.pages.length,
                          onPageChanged: (i) => setState(() => _index = i),
                          itemBuilder: (_, i) => Padding(
                            padding: EdgeInsets.fromLTRB(_hasMultiple ? 56 : 16,
                                0, _hasMultiple ? 56 : 16, 0),
                            child: DocumentViewer(
                              url: widget.pages[i].url,
                              autoLandscape: widget.pages[i].autoLandscape,
                              // Walang overlay sa ibabaw ng litrato — nasa toolbar
                              // na (− / + / ⟳) ang mga kontrol.
                              showZoomControls: false,
                              showRotateControl: false,
                              quarterTurns: _rotations[i] ?? 0,
                              // Nakikita pa rin ang buong dokumento (may espasyo
                              // sa gilid) pero may scrollbar at Ctrl+wheel zoom.
                              coverFit: false,
                              zoomController: _zoomControllerFor(i),
                              // `infinity` → pinupuno ang taas ng carousel
                              // imbes na fixed 540.
                              height: double.infinity,
                            ),
                          ),
                        ),
                      ),
                      if (_hasMultiple) ...[
                        // Ang arrow ay lalabas LANG kapag may pupuntahan — hindi
                        // na ipinapakita ang greyed-out/disabled na button.
                        if (_index > 0)
                          _arrow(
                            alignment: Alignment.centerLeft,
                            icon: Icons.chevron_left_rounded,
                            tooltip: 'Previous',
                            onTap: () => _goTo(_index - 1),
                          ),
                        if (_index < widget.pages.length - 1)
                          _arrow(
                            alignment: Alignment.centerRight,
                            icon: Icons.chevron_right_rounded,
                            tooltip: 'Next',
                            onTap: () => _goTo(_index + 1),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 10,
                          child: _dots(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Sinsikip na header (44px) — dating ~64px dahil sa default na padding ng
  /// IconButton; kailangan ang espasyo para sa dokumento, hindi sa title.
  Widget _header() {
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.deepNavy, Color(0xFF1A2E4A)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.insert_drive_file_rounded,
                color: Colors.white, size: 13),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  ZoomPaneController get _currentZoom => _zoomControllerFor(_index);

  /// Maliit na toolbar button (katulad ng sukat ng ⟳) — para pareho ang taas ng
  /// row at hindi tumaas ang header/toolbar.
  Widget _toolButton({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onTap : null,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      icon: Icon(
        icon,
        size: 18,
        color: enabled ? AppColors.deepNavy : AppColors.textTertiary,
      ),
    );
  }

  Widget _arrow({
    required Alignment alignment,
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Tooltip(
          message: tooltip,
          child: Material(
            color: AppColors.deepNavy.withValues(alpha: 0.85),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(icon, size: 22, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < widget.pages.length; i++)
          GestureDetector(
            onTap: () => _goTo(i),
            child: Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == _index
                    ? AppColors.deepNavy
                    : AppColors.deepNavy.withValues(alpha: 0.25),
              ),
            ),
          ),
      ],
    );
  }
}
