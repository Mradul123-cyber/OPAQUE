import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

void main() async {
  print('Creating padded icon for adaptive icons...');

  // Read original logo
  final originalFile = File('assets/zarq_logo_circle.png');
  if (!await originalFile.exists()) {
    print('Error: zarq_logo_circle.png not found in assets folder');
    return;
  }

  final originalBytes = await originalFile.readAsBytes();
  final originalImage = img.decodeImage(originalBytes);

  if (originalImage == null) {
    print('Error: Could not decode image');
    return;
  }

  print('Original image size: ${originalImage.width}x${originalImage.height}');

  // Create new canvas with padding (512x512 is standard for adaptive icons)
  final paddedSize = 512;
  final scaledLogoSize = (paddedSize * 0.66).round(); // Logo takes 66% of space

  // Create canvas with dark blue background matching your logo
  final paddedImage = img.Image(width: paddedSize, height: paddedSize);
  img.fill(paddedImage, color: img.ColorRgb8(26, 29, 46)); // #1A1D2E

  // Resize original logo to 66% size
  final resizedLogo = img.copyResize(
    originalImage,
    width: scaledLogoSize,
    height: scaledLogoSize,
    interpolation: img.Interpolation.linear,
  );

  // Calculate position to center the logo
  final offsetX = (paddedSize - scaledLogoSize) ~/ 2;
  final offsetY = (paddedSize - scaledLogoSize) ~/ 2;

  // Composite the resized logo onto the center of the padded canvas
  img.compositeImage(paddedImage, resizedLogo, dstX: offsetX, dstY: offsetY);

  // Save the padded version
  final paddedFile = File('assets/zarq_logo_padded.png');
  await paddedFile.writeAsBytes(img.encodePng(paddedImage));

  print('✓ Created zarq_logo_padded.png in assets folder');
  print('  Size: ${paddedSize}x${paddedSize}');
  print('  Logo scaled to: ${scaledLogoSize}x${scaledLogoSize} (66% of canvas)');
  print('  This ensures all rings (bluish outer, orange middle, Z center) are fully visible!');
  print('\nNow run: flutter pub run flutter_launcher_icons');
}
