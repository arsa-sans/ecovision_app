import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  print("Creating a test image...");
  // Create a simple 2x2 image with known values
  final image = img.Image(width: 2, height: 2);
  
  // Set pixel colors: Pixel 1: Red (255, 0, 0)
  image.setPixelRgb(0, 0, 255, 128, 64);
  
  final pixel = image.getPixel(0, 0);
  print("Pixel at 0, 0: r=${pixel.r}, g=${pixel.g}, b=${pixel.b}");
  print("Pixel class: ${pixel.runtimeType}");
  
  // Check image formats
  print("Image format: ${image.format}");
}
