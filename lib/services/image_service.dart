import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/image_transmission.dart';

const int _chunkSize = 180;

class ImageService {
  static const _chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  static final _random = Random();

  /// Compress an image for mesh transmission.
  /// [detailed] = false: 160x120 (fast), true: 200x200 (detailed)
  static Uint8List compressForMesh(Uint8List imageBytes, {bool detailed = false}) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) throw Exception('No se pudo decodificar la imagen');

    final targetWidth = detailed ? 200 : 160;
    final targetHeight = detailed ? 200 : 120;

    final resized = img.copyResize(
      decoded,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.average,
    );

    // Encode as JPEG with low quality for small size
    final quality = detailed ? 35 : 25;
    final jpg = img.encodeJpg(resized, quality: quality);

    return Uint8List.fromList(jpg);
  }

  /// Fragment a compressed image into base64 chunks of [_chunkSize] bytes each.
  static List<String> fragmentImage(Uint8List compressedImage) {
    final base64Str = base64Encode(compressedImage);
    final chunks = <String>[];

    for (int i = 0; i < base64Str.length; i += _chunkSize) {
      final end = (i + _chunkSize > base64Str.length) ? base64Str.length : i + _chunkSize;
      chunks.add(base64Str.substring(i, end));
    }

    return chunks;
  }

  /// Generate a random 4-character image ID.
  static String generateImageId() {
    return List.generate(4, (_) => _chars[_random.nextInt(_chars.length)]).join();
  }

  /// Calculate CRC16-IBM checksum (polynomial 0xA001).
  static int calculateChecksum(Uint8List data) {
    int crc = 0xFFFF;

    for (final byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x0001) != 0) {
          crc = (crc >> 1) ^ 0xA001;
        } else {
          crc >>= 1;
        }
      }
    }

    return crc & 0xFFFF;
  }

  /// Estimate transmission time in seconds.
  static double estimateTime(int totalChunks) {
    return totalChunks * 3.5;
  }

  /// Prepare a full ImageTransmission object ready to send.
  static ImageTransmission prepareTransmission(
    Uint8List originalImage,
    String tipo, {
    bool detailed = false,
  }) {
    final compressed = compressForMesh(originalImage, detailed: detailed);
    final chunks = fragmentImage(compressed);
    final checksum = calculateChecksum(compressed);
    final imageId = generateImageId();

    return ImageTransmission(
      imageId: imageId,
      tipo: tipo,
      compressedImage: compressed,
      chunks: chunks,
      checksum: checksum,
    );
  }
}
