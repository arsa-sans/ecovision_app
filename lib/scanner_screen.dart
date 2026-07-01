import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'onnx_helper.dart';
import 'waste_model.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with TickerProviderStateMixin {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _cameraReady = false;

  WasteResult? _result;
  bool _isProcessing = false;
  Timer? _inferenceTimer;

  late final AnimationController _scanLineController;
  late final Animation<double> _scanLineAnim;
  late final AnimationController _cornerController;
  late final Animation<double> _cornerAnim;
  late final AnimationController _resultSlideController;
  late final Animation<Offset> _resultSlideAnim;

  static const double _scanBoxFraction = 0.65;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initCamera();
    OnnxHelper.initialize();
  }

  void _initAnimations() {
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _scanLineAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanLineController, curve: Curves.easeInOut),
    );

    _cornerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _cornerAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _cornerController, curve: Curves.easeInOut),
    );

    _resultSlideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _resultSlideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
          parent: _resultSlideController, curve: Curves.easeOutCubic),
    );
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      _cameraController = CameraController(
        _cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _cameraController!.initialize();

      if (!mounted) return;
      setState(() => _cameraReady = true);

      _inferenceTimer = Timer.periodic(
        const Duration(milliseconds: 350),
        (_) => _captureAndInfer(),
      );
    } catch (e) {
      debugPrint('Camera init error: $e');
    }
  }

  Future<void> _captureAndInfer() async {
    if (_isProcessing ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }

    _isProcessing = true;
    try {
      final xFile = await _cameraController!.takePicture();
      final bytes = await xFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return;

      // Crop the centre square (matching the scan box on screen)
      final size =
          decoded.width < decoded.height ? decoded.width : decoded.height;
      final cropSize = (size * _scanBoxFraction).toInt();
      final offsetX = (decoded.width - cropSize) ~/ 2;
      final offsetY = (decoded.height - cropSize) ~/ 2;
      final cropped = img.copyCrop(
        decoded,
        x: offsetX,
        y: offsetY,
        width: cropSize,
        height: cropSize,
      );

      final result = await OnnxHelper.runInference(cropped);
      if (mounted && result != null) {
        setState(() => _result = result);
        if (result.isHighConfidence) {
          _resultSlideController.forward();
        } else {
          _resultSlideController.reverse();
        }
      }
    } catch (e) {
      debugPrint('Inference error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  @override
  void dispose() {
    _inferenceTimer?.cancel();
    _cameraController?.dispose();
    _scanLineController.dispose();
    _cornerController.dispose();
    _resultSlideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.5),
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Live Scanner',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: Stack(
        children: [
          // Camera preview (full screen)
          if (_cameraReady && _cameraController != null)
            Positioned.fill(
              child: CameraPreview(_cameraController!),
            )
          else
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF00E676),
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),

          // Darkened overlay outside scan box
          Positioned.fill(child: _ScanOverlay(scanFraction: _scanBoxFraction)),

          // Animated scan box
          Center(child: _buildScanBox(context)),

          // Detection label above scan box
          if (_result != null)
            Positioned(
              left: 0,
              right: 0,
              child: Center(child: _buildLabelBadge()),
            ),

          // Bottom result panel
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SlideTransition(
              position: _resultSlideAnim,
              child: _buildResultPanel(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanBox(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final boxSize = screenWidth * _scanBoxFraction;
    final result = _result;
    final Color activeColor = result != null && result.isHighConfidence
        ? Color(wasteColors[result.className] ?? 0xFF00E676)
        : const Color(0xFF00E676);

    return SizedBox(
      width: boxSize,
      height: boxSize,
      child: Stack(
        children: [
          // Animated corner brackets
          AnimatedBuilder(
            animation: _cornerAnim,
            builder: (_, __) => CustomPaint(
              size: Size(boxSize, boxSize),
              painter: _CornerPainter(
                color: activeColor.withValues(alpha: _cornerAnim.value),
                cornerLength: 28,
                strokeWidth: 3.5,
              ),
            ),
          ),
          // Animated scan line
          AnimatedBuilder(
            animation: _scanLineAnim,
            builder: (_, __) => Positioned(
              top: _scanLineAnim.value * (boxSize - 2),
              left: 0,
              right: 0,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      activeColor.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabelBadge() {
    final result = _result;
    if (result == null) return const SizedBox.shrink();
    final screenWidth = MediaQuery.of(context).size.width;
    final boxSize = screenWidth * _scanBoxFraction;
    final screenHeight = MediaQuery.of(context).size.height;
    final color = Color(wasteColors[result.className] ?? 0xFF00E676);
    final emoji = wasteEmojis[result.className] ?? '♻️';

    return Padding(
      padding: EdgeInsets.only(top: screenHeight / 2 - boxSize / 2 - 58),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          color: Colors.black.withValues(alpha: 0.75),
          border:
              Border.all(color: color.withValues(alpha: 0.7), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              result.displayName,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(result.confidence * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultPanel() {
    final result = _result;
    if (result == null || !result.isHighConfidence) {
      return const SizedBox.shrink();
    }
    final info = result.info;
    final color = Color(wasteColors[result.className] ?? 0xFF00E676);
    final emoji = wasteEmojis[result.className] ?? '♻️';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        color: const Color(0xFF0D1117).withValues(alpha: 0.96),
        border: Border(
          top: BorderSide(
              color: color.withValues(alpha: 0.4), width: 1.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: color.withValues(alpha: 0.15),
                ),
                child: Center(
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                    Text(
                      'Confidence: ${(result.confidence * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (info != null) ...[
            const SizedBox(height: 16),
            _InfoRow(
              icon: Icons.delete_outline_rounded,
              color: color,
              title: 'How to Dispose',
              content: info.disposalMethod,
            ),
            const SizedBox(height: 10),
            _InfoRow(
              icon: Icons.recycling_rounded,
              color: color,
              title: 'Recycling Ideas',
              content: info.recyclingIdeas,
            ),
            const SizedBox(height: 10),
            _InfoRow(
              icon: Icons.nature_people_rounded,
              color: color,
              title: 'Environmental Impact',
              content: info.environmentalImpact,
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Custom painters
// ─────────────────────────────────────────────

class _ScanOverlay extends StatelessWidget {
  final double scanFraction;
  const _ScanOverlay({required this.scanFraction});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _OverlayPainter(fraction: scanFraction),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final double fraction;
  const _OverlayPainter({required this.fraction});

  @override
  void paint(Canvas canvas, Size size) {
    final boxSize = size.width * fraction;
    final left = (size.width - boxSize) / 2;
    final top = (size.height - boxSize) / 2;

    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.55);
    final full = Rect.fromLTWH(0, 0, size.width, size.height);
    final hole = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, boxSize, boxSize),
      const Radius.circular(4),
    );

    final path = Path()
      ..addRect(full)
      ..addRRect(hole)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => old.fraction != fraction;
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double cornerLength;
  final double strokeWidth;

  const _CornerPainter({
    required this.color,
    required this.cornerLength,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    final c = cornerLength;

    // Top-left
    canvas.drawLine(const Offset(0, 0), Offset(c, 0), paint);
    canvas.drawLine(const Offset(0, 0), Offset(0, c), paint);
    // Top-right
    canvas.drawLine(Offset(w, 0), Offset(w - c, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, c), paint);
    // Bottom-left
    canvas.drawLine(Offset(0, h), Offset(c, h), paint);
    canvas.drawLine(Offset(0, h), Offset(0, h - c), paint);
    // Bottom-right
    canvas.drawLine(Offset(w, h), Offset(w - c, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w, h - c), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) =>
      old.color != color || old.cornerLength != cornerLength;
}

// ─────────────────────────────────────────────
// Info Row Widget
// ─────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String content;

  const _InfoRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                content,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.7),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
