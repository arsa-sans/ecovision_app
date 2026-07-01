import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'onnx_helper.dart';
import 'waste_model.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen>
    with SingleTickerProviderStateMixin {
  File? _selectedImage;
  WasteResult? _result;
  bool _isAnalyzing = false;
  String? _errorMsg;

  late final AnimationController _resultAnimController;
  late final Animation<double> _resultFadeAnim;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _resultAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _resultFadeAnim = CurvedAnimation(
      parent: _resultAnimController,
      curve: Curves.easeOut,
    );
    OnnxHelper.initialize();
  }

  @override
  void dispose() {
    _resultAnimController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? xFile = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );
      if (xFile == null) return;

      setState(() {
        _selectedImage = File(xFile.path);
        _result = null;
        _errorMsg = null;
        _resultAnimController.reset();
      });
    } catch (e) {
      setState(() => _errorMsg = 'Failed to pick image: $e');
    }
  }

  Future<void> _analyzeImage() async {
    if (_selectedImage == null) return;
    setState(() {
      _isAnalyzing = true;
      _result = null;
      _errorMsg = null;
      _resultAnimController.reset();
    });

    try {
      final Uint8List bytes = await _selectedImage!.readAsBytes();
      final result = await OnnxHelper.runInferenceOnBytes(bytes);
      if (mounted) {
        setState(() {
          _result = result;
          _isAnalyzing = false;
        });
        _resultAnimController.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          _errorMsg = 'Analysis failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gallery Analysis'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildImagePicker(),
            const SizedBox(height: 20),
            _buildPickButtons(),
            const SizedBox(height: 20),
            if (_selectedImage != null) ...[
              _buildAnalyzeButton(),
              const SizedBox(height: 24),
            ],
            if (_isAnalyzing) _buildLoadingWidget(),
            if (_errorMsg != null) _buildErrorWidget(),
            if (_result != null)
              FadeTransition(
                opacity: _resultFadeAnim,
                child: _buildResultCard(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePicker() {
    return GestureDetector(
      onTap: () => _pickImage(ImageSource.gallery),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 260,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xFF161B22),
          border: Border.all(
            color: _selectedImage != null
                ? const Color(0xFF00E676).withValues(alpha: 0.4)
                : const Color(0xFF30363D),
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: _selectedImage != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(_selectedImage!, fit: BoxFit.cover),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        color: Colors.black.withValues(alpha: 0.65),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit, color: Colors.white, size: 12),
                          SizedBox(width: 4),
                          Text(
                            'Change',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF00E676).withValues(alpha: 0.1),
                    ),
                    child: const Icon(
                      Icons.add_photo_alternate_rounded,
                      color: Color(0xFF00E676),
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Tap to select an image',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Choose from gallery or take a photo',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPickButtons() {
    return Row(
      children: [
        Expanded(
          child: _SourceButton(
            icon: Icons.photo_library_rounded,
            label: 'Gallery',
            color: const Color(0xFF42A5F5),
            onTap: () => _pickImage(ImageSource.gallery),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SourceButton(
            icon: Icons.camera_alt_rounded,
            label: 'Camera',
            color: const Color(0xFF00E676),
            onTap: () => _pickImage(ImageSource.camera),
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyzeButton() {
    return FilledButton.icon(
      onPressed: _isAnalyzing ? null : _analyzeImage,
      icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
      label: const Text('Analyze Waste'),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF161B22),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        children: [
          const CircularProgressIndicator(
            color: Color(0xFF00E676),
            strokeWidth: 2.5,
          ),
          const SizedBox(height: 16),
          Text(
            'Analyzing image...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFFFF5252).withValues(alpha: 0.1),
        border: Border.all(
            color: const Color(0xFFFF5252).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFF5252), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMsg ?? 'An error occurred.',
              style:
                  const TextStyle(color: Color(0xFFFF5252), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    final result = _result!;
    final info = result.info;
    final color = Color(wasteColors[result.className] ?? 0xFF00E676);
    final emoji = wasteEmojis[result.className] ?? '♻️';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF161B22),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              gradient: LinearGradient(
                colors: [
                  color.withValues(alpha: 0.18),
                  Colors.transparent,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: color.withValues(alpha: 0.15),
                  ),
                  child: Center(
                    child: Text(emoji,
                        style: const TextStyle(fontSize: 26)),
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
                          fontSize: 22,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: result.confidence,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.1),
                                color: color,
                                minHeight: 6,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${(result.confidence * 100).toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (info != null) ...[
            Divider(height: 1, color: color.withValues(alpha: 0.2)),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _ResultInfoTile(
                    icon: Icons.delete_outline_rounded,
                    color: color,
                    title: 'How to Dispose',
                    content: info.disposalMethod,
                  ),
                  const SizedBox(height: 14),
                  _ResultInfoTile(
                    icon: Icons.recycling_rounded,
                    color: color,
                    title: 'Recycling Ideas',
                    content: info.recyclingIdeas,
                  ),
                  const SizedBox(height: 14),
                  _ResultInfoTile(
                    icon: Icons.nature_people_rounded,
                    color: color,
                    title: 'Environmental Impact',
                    content: info.environmentalImpact,
                  ),
                  if (info.notes != null) ...[
                    const SizedBox(height: 14),
                    _ResultInfoTile(
                      icon: Icons.lightbulb_outline_rounded,
                      color: const Color(0xFFFFCA28),
                      title: 'Tip',
                      content: info.notes!,
                    ),
                  ],
                ],
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'No additional info available for this category.',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5)),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Widgets
// ─────────────────────────────────────────────

class _SourceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SourceButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultInfoTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String content;

  const _ResultInfoTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withValues(alpha: 0.07),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 12),
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
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.75),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
