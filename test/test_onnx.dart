import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

void main() {
  test('Compare preprocessing with Python', () {
    print("Loading test image in Dart...");
    final imageFile = File('assets/test_image.jpg');
    expect(imageFile.existsSync(), isTrue);
    final bytes = imageFile.readAsBytesSync();
    
    final image = img.decodeImage(bytes);
    expect(image, isNotNull);
    print("Decoded image size: ${image!.width}x${image.height}");
    
    // Normalization constants
    const List<double> mean = [0.485, 0.456, 0.406];
    const List<double> std = [0.229, 0.224, 0.225];
    
    // Resize image (same as OnnxHelper)
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
    
    // Calculate statistics
    double sum = 0.0;
    double minVal = tensor[0];
    double maxVal = tensor[0];
    for (int i = 0; i < tensor.length; i++) {
      final val = tensor[i];
      sum += val;
      if (val < minVal) minVal = val;
      if (val > maxVal) maxVal = val;
    }
    double meanVal = sum / tensor.length;
    
    print("\n--- Dart Preprocessing Results ---");
    print("Preprocessed flat size: ${tensor.length}");
    print("First 10 values: ${tensor.sublist(0, 10)}");
    print("Sum of values: $sum");
    print("Mean value: $meanVal");
    print("Min value: $minVal");
    print("Max value: $maxVal");
    
    // Run inference
    OrtEnv.instance.init();
    final modelFile = File('assets/models/best_model.onnx');
    final session = OrtSession.fromBuffer(modelFile.readAsBytesSync(), OrtSessionOptions());
    
    final inputTensor = OrtValueTensor.createTensorWithDataList(tensor, [1, 3, 224, 224]);
    final inputs = {'input': inputTensor};
    final runOptions = OrtRunOptions();
    final outputs = session.run(runOptions, inputs);
    
    final outputData = outputs.first!.value as List<dynamic>;
    final logits = (outputData.first as List<dynamic>).map((e) => (e as num).toDouble()).toList();
    
    // Softmax
    final maxLogit = logits.reduce((a, b) => a > b ? a : b);
    double sumExp = 0.0;
    final expLogits = logits.map((l) {
      final ex = _exp(l - maxLogit);
      sumExp += ex;
      return ex;
    }).toList();
    final probs = expLogits.map((e) => e / sumExp).toList();
    
    final classNames = ['glass', 'hazardous', 'metal', 'organic', 'paper', 'plastic', 'textile'];
    int predIdx = 0;
    double maxProb = probs[0];
    for (int i = 1; i < probs.length; i++) {
      if (probs[i] > maxProb) {
        maxProb = probs[i];
        predIdx = i;
      }
    }
    
    print("Raw logits: $logits");
    print("Probabilities: $probs");
    print("Predicted class: ${classNames[predIdx]} (${(maxProb * 100).toStringAsFixed(2)}%)");
    
    // Clean up
    inputTensor.release();
    runOptions.release();
    for (final element in outputs) {
      element?.release();
    }
    session.release();
  });
}

double _exp(double x) {
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
