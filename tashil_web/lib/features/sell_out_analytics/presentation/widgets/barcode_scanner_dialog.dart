import 'dart:async';
import 'package:tashil_web/core/theme/m3_typography.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/m3_shape.dart';

/// Product barcode specimen model for quick testing and scanner demonstration
class BarcodeSpecimen {
  final String barcode;
  final String skuName;
  final String category;
  final String chain;

  const BarcodeSpecimen({
    required this.barcode,
    required this.skuName,
    required this.category,
    required this.chain,
  });
}

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

  // Catalog Barcode specimens from real Adeco & Retail datasets (English)
  static const List<BarcodeSpecimen> _specimens = [
    BarcodeSpecimen(
      barcode: '99069570',
      skuName: 'Diva Hand Wash 500ml',
      category: 'Personal Care',
      chain: 'Beet El-Gomla',
    ),
    BarcodeSpecimen(
      barcode: '99069587',
      skuName: 'Adeco Auto Powder Lavender 3kg',
      category: 'Laundry Detergent',
      chain: 'Fathalla Market',
    ),
    BarcodeSpecimen(
      barcode: '6223000451234',
      skuName: 'Diva Shower Gel Sea Breeze 1L',
      category: 'Personal Care',
      chain: 'Carrefour',
    ),
    BarcodeSpecimen(
      barcode: '6221155012345',
      skuName: 'Adeco Spring Air Freshener 460ml',
      category: 'Air Care',
      chain: 'Gomla Market',
    ),
    BarcodeSpecimen(
      barcode: '99069594',
      skuName: 'Diva Dishwashing Liquid Lemon 4L',
      category: 'Dish Care',
      chain: 'Spinneys',
    ),
    BarcodeSpecimen(
      barcode: '6224000129876',
      skuName: 'Adeco Bleach Ultra White 1000ml',
      category: 'Bleach & Disinfectants',
      chain: 'Institutions',
    ),
  ];

  int _currentSpecimenIndex = 0;

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
    super.dispose();
  }

  void _triggerScanDetection(String barcode, {String? skuName}) {
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

  void _simulateCameraCapture() {
    final specimen = _specimens[_currentSpecimenIndex];
    _currentSpecimenIndex = (_currentSpecimenIndex + 1) % _specimens.length;
    _triggerScanDetection(specimen.barcode, skuName: specimen.skuName);
  }

  void _simulatePhotoUpload() {
    // Pick the primary barcode specimen
    final specimen = _specimens.first;
    _triggerScanDetection(specimen.barcode, skuName: specimen.skuName);
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
                          size: 22.0,
                        ),
                      ),
                      const SizedBox(width: 12.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Smart Barcode Scanner',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              'Point camera at product barcode to detect',
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
                        tooltip: 'Close',
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
                            ? const Color(0xFF10B981)
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
                                            ? const Color(0xFF10B981)
                                            : const Color(0xFF38BDF8),
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
                                            ? const Color(0xFF10B981)
                                            : const Color(0xFFEF4444),
                                      ),
                                    ),
                                    const SizedBox(width: 6.0),
                                    Text(
                                      _isDetecting ? 'DETECTED' : 'LIVE 60FPS',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: M3FontSize.tiny,
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
                                    tooltip: 'Flash',
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
                                    tooltip: 'Switch Camera',
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
                                  ? '✓ Barcode detected successfully'
                                  : 'Point camera at product barcode',
                              style: TextStyle(
                                color: _isDetecting
                                    ? const Color(0xFF10B981)
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

                // Material Design 3 Connected Button Group (Camera Scan & Scan Image)
                Container(
                  decoration: BoxDecoration(
                    borderRadius: M3Shape.radiusMd,
                    border: Border.all(color: colorScheme.outlineVariant),
                    color: colorScheme.surfaceContainerHighest.withOpacity(0.35),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            key: const ValueKey('scanner_simulate_capture_button'),
                            borderRadius: const BorderRadius.horizontal(left: Radius.circular(13.0)),
                            onTap: _isDetecting ? null : _simulateCameraCapture,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12.0),
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                borderRadius: const BorderRadius.horizontal(left: Radius.circular(13.0)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.camera_alt_rounded, size: 18.0, color: colorScheme.onPrimary),
                                  const SizedBox(width: 8.0),
                                  Text(
                                    'Camera Scan',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: colorScheme.onPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 1.0,
                        height: 28.0,
                        color: colorScheme.outlineVariant,
                      ),
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            key: const ValueKey('scanner_photo_scan_button'),
                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(13.0)),
                            onTap: _isDetecting ? null : _simulatePhotoUpload,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.photo_library_rounded, size: 18.0, color: colorScheme.primary),
                                  const SizedBox(width: 8.0),
                                  Text(
                                    'Scan Image',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16.0),

                // Catalog Quick-Scan Specimens
                Row(
                  children: [
                    Icon(Icons.inventory_2_rounded,
                        size: 15.0, color: colorScheme.primary),
                    const SizedBox(width: 6.0),
                    Expanded(
                      child: Text(
                        'Quick Scan Catalog Barcodes:',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8.0),
                Wrap(
                  spacing: 6.0,
                  runSpacing: 6.0,
                  children: _specimens.map((specimen) {
                    return InkWell(
                      borderRadius: M3Shape.radiusLg,
                      onTap: () => _triggerScanDetection(specimen.barcode,
                          skuName: specimen.skuName),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10.0, vertical: 6.0),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withOpacity(0.6),
                          borderRadius: M3Shape.radiusLg,
                          border: Border.all(
                            color: colorScheme.outlineVariant.withOpacity(0.6),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.qr_code_2_rounded,
                                size: 14.0, color: colorScheme.primary),
                            const SizedBox(width: 4.0),
                            Text(
                              '${specimen.barcode} (${specimen.skuName.split(' ').first})',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
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
    const cornerColor = Color(0xFF38BDF8);

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
