// lib/presentation/shared/widgets/branded_loading_screen.dart
//
// Ang BRANDED na loading screen: logo + "JIRETA" + gold progress bar, kapareho
// ng hitsura ng splash screen.
//
// BAKIT: kapag binuksan muli ang app, may sandali pang nagre-restore ng session
// (secure storage + server check). Dati, ang login page ay nagpapakita ng
// HUBAD na spinner sa navy na background sa sandaling iyon — kaya parang
// "loading screen" ang sumalubong sa user imbes na ang splash. Gamit ito, ang
// nakikita ay tuloy-tuloy na branding mula splash → pag-load → login/MPIN.
import 'package:flutter/material.dart';

import '../../../core/constants/asset_constants.dart';
import '../../../core/theme/app_colors.dart';

class BrandedLoadingScreen extends StatefulWidget {
  const BrandedLoadingScreen({
    super.key,
    this.message = 'Preparing your experience…',
  });

  /// Ang maliit na tekstong nasa ilalim ng progress bar.
  final String message;

  @override
  State<BrandedLoadingScreen> createState() => _BrandedLoadingScreenState();
}

class _BrandedLoadingScreenState extends State<BrandedLoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _scaleAnim = Tween<double>(begin: 0.92, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Putî ang background — kapareho ng splash screen, kaya walang "flash" ng
    // ibang kulay sa paglipat nito patungo sa login / MPIN screen.
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: ScaleTransition(
              scale: _scaleAnim,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Logo (puting bilog na may gintong ring) ──
                  Container(
                    width: 100,
                    height: 100,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.gold.withValues(alpha: 0.35),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        AssetConstants.logoJpg,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),

                  // ── Brand name ──
                  const Text(
                    'JIRETA',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      color: AppColors.deepNavy,
                      letterSpacing: 7,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 36),

                  // ── Gold progress bar + mensahe ──
                  SizedBox(
                    width: 148,
                    height: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: Stack(
                        children: [
                          Container(
                            color: AppColors.deepNavy.withValues(alpha: 0.08),
                          ),
                          const Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.all(
                                Radius.circular(99),
                              ),
                              child: LinearProgressIndicator(
                                minHeight: 3,
                                color: AppColors.gold,
                                backgroundColor: Colors.transparent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.deepNavy.withValues(alpha: 0.55),
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
