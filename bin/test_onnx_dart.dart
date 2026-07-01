import 'dart:io';
import 'dart:typed_data';
import 'package:onnxruntime/onnxruntime.dart';

void main() {
  print("Initializing OrtEnv...");
  try {
    OrtEnv.instance.init();
    print("OrtEnv initialized successfully.");
    
    final modelFile = File('assets/models/best_model.onnx');
    if (!modelFile.existsSync()) {
      print("Model file not found!");
      return;
    }
    final bytes = modelFile.readAsBytesSync();
    print("Model loaded, size: ${bytes.length} bytes");
    
    final sessionOptions = OrtSessionOptions();
    final session = OrtSession.fromBuffer(bytes, sessionOptions);
    print("OrtSession created successfully.");
    
    // Create input data (1 * 3 * 224 * 224 zeros/ones just to test)
    final inputData = Float32List(1 * 3 * 224 * 224);
    // Fill with some pattern or zeros
    for (int i = 0; i < inputData.length; i++) {
      inputData[i] = 0.0;
    }
    
    final inputTensor = OrtValueTensor.createTensorWithDataList(
      inputData,
      [1, 3, 224, 224],
    );
    
    final inputs = {'input': inputTensor};
    final runOptions = OrtRunOptions();
    print("Running inference...");
    final outputs = session.run(runOptions, inputs);
    
    if (outputs.isEmpty || outputs.first == null) {
      print("Inference returned empty output!");
      return;
    }
    
    final outputData = outputs.first!.value as List<dynamic>;
    print("Output raw shape/type: ${outputData.runtimeType}");
    print("First row type: ${outputData.first.runtimeType}");
    print("First row data: ${outputData.first}");
    
    // Clean up
    inputTensor.release();
    runOptions.release();
    for (final element in outputs) {
      element?.release();
    }
    session.release();
    print("Done.");
  } catch (e, stack) {
    print("Error during test: $e");
    print(stack);
  }
}
