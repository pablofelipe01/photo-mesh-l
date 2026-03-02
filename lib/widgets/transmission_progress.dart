import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../models/image_transmission.dart';

class TransmissionProgressCard extends StatelessWidget {
  final ImageTransmission transmission;
  final VoidCallback? onCancel;

  const TransmissionProgressCard({
    super.key,
    required this.transmission,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: _backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icon, color: _iconColor, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    transmission.progressText,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _textColor,
                    ),
                  ),
                ),
                if (_canCancel && onCancel != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: onCancel,
                    tooltip: 'Cancelar',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            if (_showProgress) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: transmission.progress,
                  backgroundColor: Colors.grey.shade300,
                  color: _progressColor,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(transmission.progress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  Text(
                    '${transmission.chunksSent}/${transmission.chunks.length} partes',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ],
            if (transmission.state == ImageTransmissionState.waitingResult) ...[
              const SizedBox(height: 8),
              const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool get _canCancel {
    return transmission.state == ImageTransmissionState.sending ||
        transmission.state == ImageTransmissionState.waitingAck ||
        transmission.state == ImageTransmissionState.retransmitting;
  }

  bool get _showProgress {
    return transmission.state == ImageTransmissionState.sending ||
        transmission.state == ImageTransmissionState.retransmitting;
  }

  Color get _backgroundColor {
    switch (transmission.state) {
      case ImageTransmissionState.error:
      case ImageTransmissionState.cancelled:
        return Colors.red.shade50;
      case ImageTransmissionState.completed:
        return Colors.green.shade50;
      case ImageTransmissionState.retransmitting:
        return Colors.orange.shade50;
      default:
        return Colors.blue.shade50;
    }
  }

  Color get _progressColor {
    if (transmission.state == ImageTransmissionState.retransmitting) {
      return Colors.orange;
    }
    return Colors.green;
  }

  IconData get _icon {
    switch (transmission.state) {
      case ImageTransmissionState.sending:
        return Icons.cloud_upload;
      case ImageTransmissionState.waitingAck:
        return Icons.hourglass_top;
      case ImageTransmissionState.retransmitting:
        return Icons.replay;
      case ImageTransmissionState.waitingResult:
        return Icons.psychology;
      case ImageTransmissionState.completed:
        return Icons.check_circle;
      case ImageTransmissionState.error:
        return Icons.error;
      case ImageTransmissionState.cancelled:
        return Icons.cancel;
      default:
        return Icons.photo_camera;
    }
  }

  Color get _iconColor {
    switch (transmission.state) {
      case ImageTransmissionState.error:
      case ImageTransmissionState.cancelled:
        return Colors.red;
      case ImageTransmissionState.completed:
        return Colors.green;
      case ImageTransmissionState.retransmitting:
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  Color get _textColor {
    switch (transmission.state) {
      case ImageTransmissionState.error:
      case ImageTransmissionState.cancelled:
        return Colors.red.shade700;
      case ImageTransmissionState.completed:
        return Colors.green.shade700;
      case ImageTransmissionState.retransmitting:
        return Colors.orange.shade700;
      default:
        return Colors.blue.shade700;
    }
  }
}
