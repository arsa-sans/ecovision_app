import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'waste_model.dart';

class OnnxHelper {
  static const List<String> classNames = [
    'glass',
    'hazardous',
    'metal',
    'organic',
    'paper',
    'plastic',
    'textile',
  ];

  // ImageNet normalization constants
  static const List<double> mean = [0.485, 0.456, 0.406];
  static const List<double> std = [0.229, 0.224, 0.225];

  static OrtSession? _session;
  static Map<String, WasteInfo>? _knowledgeBase;
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    // Initialize OrtEnv
    OrtEnv.instance.init();

    // Load model from assets
    final rawAsset = await rootBundle.load('assets/models/best_model.onnx');
    final bytes = rawAsset.buffer.asUint8List();
    final sessionOptions = OrtSessionOptions();
    _session = OrtSession.fromBuffer(bytes, sessionOptions);

    // Load knowledge base
    final jsonStr = await rootBundle.loadString('assets/waste_info.json');
    final jsonMap = json.decode(jsonStr) as Map<String, dynamic>;
    _knowledgeBase = jsonMap.map(
      (key, value) =>
          MapEntry(key, WasteInfo.fromJson(value as Map<String, dynamic>)),
    );

    _initialized = true;
  }

  /// Preprocess a raw [img.Image] to a [Float32List] tensor (CHW, normalized).
  static Float32List _preprocessImage(img.Image image) {
    final resized = img.copyResize(image, width: 224, height: 224);
    final tensor = Float32List(3 * 224 * 224);

    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        final pixel = resized.getPixel(x, y);
        final r = pixel.r / 255.0;
        final g = pixel.g / 255.0;
        final b = pixel.b / 255.0;

        final idx = y * 224 + x;
        tensor[idx] = ((r - mean[0]) / std[0]).toDouble();
        tensor[224 * 224 + idx] = ((g - mean[1]) / std[1]).toDouble();
        tensor[2 * 224 * 224 + idx] = ((b - mean[2]) / std[2]).toDouble();
      }
    }
    return tensor;
  }

  /// Run inference on an already-decoded [img.Image].
  static Future<WasteResult?> runInference(img.Image image) async {
    if (_session == null) await initialize();

    final inputData = _preprocessImage(image);
    final inputTensor = OrtValueTensor.createTensorWithDataList(
      inputData,
      [1, 3, 224, 224],
    );

    final runOptions = OrtRunOptions();
    final inputs = {'input': inputTensor};
    final outputs = await _session!.runAsync(runOptions, inputs);

    inputTensor.release();
    runOptions.release();

    if (outputs == null || outputs.isEmpty) return null;

    final outputData = outputs.first?.value as List<dynamic>?;
    for (final element in outputs) {
      element?.release();
    }

    if (outputData == null) return null;

    // outputData is List<List<double>> with shape [1, 7]
    final logits = (outputData.first as List<dynamic>)
        .map((e) => (e as num).toDouble())
        .toList();

    // Softmax
    final maxLogit = logits.reduce((a, b) => a > b ? a : b);
    final expLogits = logits.map((l) => _exp(l - maxLogit)).toList();
    final sumExp = expLogits.reduce((a, b) => a + b);
    final probabilities = expLogits.map((e) => e / sumExp).toList();

    // Argmax
    double maxProb = probabilities[0];
    int maxIdx = 0;
    for (int i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > maxProb) {
        maxProb = probabilities[i];
        maxIdx = i;
      }
    }

    final className = classNames[maxIdx];
    final info = _knowledgeBase?[className];

    return WasteResult(
      className: className,
      confidence: maxProb,
      info: info,
    );
  }

  /// Run inference on raw bytes (jpg/png from file or camera).
  static Future<WasteResult?> runInferenceOnBytes(Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    return runInference(image);
  }

  static double _exp(double x) {
    if (x > 88) return 1.5e38;
    if (x < -88) return 0.0;
    double result = 1.0;
    double term = 1.0;
    for (int i = 1; i <= 20; i++) {
      term *= x / i;
      result += term;
      if (term.abs() < 1e-10) break;
    }
    return result;
  }

  static void dispose() {
    _session?.release();
    _session = null;
    _initialized = false;
  }
}
