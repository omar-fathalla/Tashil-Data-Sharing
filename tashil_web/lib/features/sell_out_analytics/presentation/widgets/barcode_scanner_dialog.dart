import 'dart:async';
import 'package:tashil_web/core/theme/m3_palette.dart';
import 'package:tashil_web/core/theme/m3_typography.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/m3_shape.dart';

/// Material Design 3 Barcode Camera Scanner Dialog
/// Supports live camera viewfinder simulation, photo/image scan,
/// instant catalog detection, and direct barcode entry.
class BarcodeScannerDialog extends StatefulWidget {
  final ValueChanged<String>? onBarcodeDetected;

  const BarcodeScannerDialog({
    super.key,
    this.onBarcodeDetected,
  });

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const BarcodeScannerDialog(),
    );
  }

  @override
  State<BarcodeScannerDialog> createState() => _BarcodeScannerDialogState();
}

class _BarcodeScannerDialogState extends State<BarcodeScannerDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _laserController;
  late final Animation<double> _laserAnimation;

  bool _isFlashOn = false;
  bool _isBackCamera = true;
  bool _isScanning = true;
  bool _isDetecting = false;

  final TextEditingController _manualController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _laserAnimation = Tween<double>(begin: 0.15, end: 0.85).animate(
      CurvedAnimation(
        parent: _laserController,
        curve: Curves.easeInOutSine,
      ),
    );
  }

  @override
  void dispose() {
    _laserController.dispose();
    _manualController.dispose();
    super.dispose();
  }

  void _triggerScanDetection(String barcode) {
    if (_isDetecting) return;
    setState(() {
      _isDetecting = true;
      _isScanning = false;
    });

    // Provide visual & feedback confirmation
    Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      widget.onBarcodeDetected?.call(barcode);
      Navigator.of(context).pop(barcode);
    });
  }

  void _submitManualBarcode() {
    final code = _manualController.text.trim();
    if (code.isEmpty) return;
    _triggerScanDetection(code);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final size = MediaQuery.sizeOf(context);
    final isCompact = size.width < 600.0;

    return Dialog(
      backgroundColor: colorScheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 6.0,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16.0 : 40.0,
        vertical: isCompact ? 24.0 : 40.0,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: M3Shape.radiusXl,
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 480.0,
            maxHeight: size.height * 0.88,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Dialog Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8.0),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: M3Shape.radiusMd,
                        ),
                        child: Icon(
                          Icons.qr_code_scanner_rounded,
                          color: colorScheme.onPrimaryContainer,
                          size: 24.0,
                        ),
                      ),
                      const SizedBox(width: 12.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'امسح الباركود',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              'وجّه الكاميرا نحو الباركود',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'إغلاق',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16.0),

                // Live Camera Viewfinder Simulation
                ClipRRect(
                  borderRadius: M3Shape.radiusLg,
                  child: Container(
                    height: 230.0,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1117),
                      borderRadius: M3Shape.radiusLg,
                      border: Border.all(
                        color: _isDetecting
                            ? M3Palette.emerald
                            : colorScheme.primary.withOpacity(0.6),
                        width: 2.0,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Background camera grid & optics effect
                        CustomPaint(
                          size: const Size(double.infinity, 230.0),
                          painter: _CameraGridPainter(),
                        ),

                        // Animated Laser Line
                        if (_isScanning)
                          AnimatedBuilder(
                            animation: _laserAnimation,
                            builder: (context, child) {
                              return Positioned(
                                top: 230.0 * _laserAnimation.value,
                                left: 32.0,
                                right: 32.0,
                                child: Container(
                                  height: 3.0,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        colorScheme.primary.withOpacity(0.0),
                                        _isDetecting
                                            ? M3Palette.emerald
                                            : M3Palette.sky,
                                        colorScheme.primary.withOpacity(0.0),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),

                        // Corner Target Reticles
                        const _ScannerReticle(),

                        // Top camera toolbar controls (Flash & Camera Flip)
                        Positioned(
                          top: 10.0,
                          left: 12.0,
                          right: 12.0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8.0, vertical: 4.0),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  borderRadius: M3Shape.radiusSm,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8.0,
                                      height: 8.0,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _isDetecting
                                            ? M3Palette.emerald
                                            : const Color(0xFFEF4444),
                                      ),
                                    ),
                                    const SizedBox(width: 6.0),
                                    Text(
                                      _isDetecting ? 'DETECTED' : 'LIVE 60FPS',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: M3FontSize.labelSmall,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      _isFlashOn
                                          ? Icons.flash_on_rounded
                                          : Icons.flash_off_rounded,
                                      color: _isFlashOn
                                          ? const Color(0xFFFBBF24)
                                          : Colors.white70,
                                      size: 20.0,
                                    ),
                                    tooltip: 'الفلاش',
                                    onPressed: () =>
                                        setState(() => _isFlashOn = !_isFlashOn),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      _isBackCamera
                                          ? Icons.camera_rear_rounded
                                          : Icons.camera_front_rounded,
                                      color: Colors.white70,
                                      size: 20.0,
                                    ),
                                    tooltip: 'تبديل الكاميرا',
                                    onPressed: () => setState(
                                        () => _isBackCamera = !_isBackCamera),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Bottom Center Instruction Label
                        Positioned(
                          bottom: 12.0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12.0, vertical: 5.0),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.7),
                              borderRadius: M3Shape.radiusMd,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.15),
                              ),
                            ),
                            child: Text(
                              _isDetecting
                                  ? 'تم التعرّف على الباركود'
                                  : 'وجّه الكاميرا نحو الباركود',
                              style: TextStyle(
                                color: _isDetecting
                                    ? M3Palette.emerald
                                    : Colors.white,
                                fontSize: M3FontSize.bodySmall,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16.0),

                // Manual barcode entry
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('scanner_manual_barcode_field'),
                        controller: _manualController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _submitManualBarcode(),
                        decoration: const InputDecoration(
                          labelText: 'أدخل الباركود',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    FilledButton(
                      key: const ValueKey('scanner_manual_submit_button'),
                      onPressed: _isDetecting ? null : _submitManualBarcode,
                      child: const Text('بحث'),
                    ),
                  ],
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

/// Draws high-tech camera scanner target corner reticles
class _ScannerReticle extends StatelessWidget {
  const _ScannerReticle();

  @override
  Widget build(BuildContext context) {
    const cornerSize = 22.0;
    const cornerWidth = 3.0;
    const cornerColor = M3Palette.sky;

    return Center(
      child: SizedBox(
        width: 200.0,
        height: 120.0,
        child: Stack(
          children: [
            // Top Left Corner
            Positioned(
              left: 0,
              top: 0,
              child: Container(
                width: cornerSize,
                height: cornerWidth,
                color: cornerColor,
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              child: Container(
                width: cornerWidth,
                height: cornerSize,
                color: cornerColor,
              ),
            ),

            // Top Right Corner
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: cornerSize,
                height: cornerWidth,
                color: cornerColor,
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: cornerWidth,
                height: cornerSize,
                color: cornerColor,
              ),
            ),

            // Bottom Left Corner
            Positioned(
              left: 0,
              bottom: 0,
              child: Container(
                width: cornerSize,
                height: cornerWidth,
                color: cornerColor,
              ),
            ),
            Positioned(
              left: 0,
              bottom: 0,
              child: Container(
                width: cornerWidth,
                height: cornerSize,
                color: cornerColor,
              ),
            ),

            // Bottom Right Corner
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: cornerSize,
                height: cornerWidth,
                color: cornerColor,
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: cornerWidth,
                height: cornerSize,
                color: cornerColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for camera preview grid
class _CameraGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..strokeWidth = 1.0;

    // Vertical rule of thirds
    final thirdW = size.width / 3;
    canvas.drawLine(Offset(thirdW, 0), Offset(thirdW, size.height), paint);
    canvas.drawLine(Offset(thirdW * 2, 0), Offset(thirdW * 2, size.height), paint);

    // Horizontal rule of thirds
    final thirdH = size.height / 3;
    canvas.drawLine(Offset(0, thirdH), Offset(size.width, thirdH), paint);
    canvas.drawLine(Offset(0, thirdH * 2), Offset(size.width, thirdH * 2), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
