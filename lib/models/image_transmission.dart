import 'dart:typed_data';

import 'chat_message.dart';

class ImageTransmission {
  final String imageId;
  final String tipo;
  Uint8List? compressedImage;
  List<String> chunks;
  int checksum;
  ImageTransmissionState state;
  int chunksSent;
  int chunksConfirmed;
  List<int> missingChunks;
  int retryRound;
  String? resultText;
  List<String> resultParts;
  int totalResultParts;
  String? errorMessage;
  final DateTime startedAt;

  ImageTransmission({
    required this.imageId,
    required this.tipo,
    this.compressedImage,
    List<String>? chunks,
    this.checksum = 0,
    this.state = ImageTransmissionState.idle,
    this.chunksSent = 0,
    this.chunksConfirmed = 0,
    List<int>? missingChunks,
    this.retryRound = 0,
    this.resultText,
    List<String>? resultParts,
    this.totalResultParts = 0,
    this.errorMessage,
    DateTime? startedAt,
  })  : chunks = chunks ?? [],
        missingChunks = missingChunks ?? [],
        resultParts = resultParts ?? [],
        startedAt = startedAt ?? DateTime.now();

  double get progress {
    if (chunks.isEmpty) return 0;
    return chunksSent / chunks.length;
  }

  String get progressText {
    switch (state) {
      case ImageTransmissionState.sending:
        return 'Enviando foto... $chunksSent/${chunks.length}';
      case ImageTransmissionState.waitingAck:
        return 'Esperando confirmacion...';
      case ImageTransmissionState.retransmitting:
        return 'Reenviando ${missingChunks.length} partes (intento $retryRound/4)...';
      case ImageTransmissionState.waitingResult:
        return 'Foto recibida. Analizando...';
      case ImageTransmissionState.completed:
        return 'Diagnostico recibido';
      case ImageTransmissionState.error:
        return errorMessage ?? 'Error al enviar';
      case ImageTransmissionState.cancelled:
        return 'Envio cancelado';
      default:
        return '';
    }
  }

  String get estimatedTimeText {
    final totalSeconds = (chunks.length * 3.5).ceil();
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes > 0) {
      return '~${minutes}m ${seconds}s';
    }
    return '~${seconds}s';
  }
}

class ImageResult {
  final String imageId;
  final String text;
  final bool isComplete;

  ImageResult({
    required this.imageId,
    required this.text,
    this.isComplete = false,
  });
}
