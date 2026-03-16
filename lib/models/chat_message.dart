enum ChatMessageType {
  text,
  imageProgress,
  imageResult,
  imageError,
  system,
  sessionResult,
  sessionEnd,
}

class ChatMessage {
  final String id;
  final String messageText;
  final int fromNodeId;
  final String fromNodeName;
  final DateTime timestamp;
  final bool isMine;
  final ChatMessageType type;
  final String? imageId;
  final String? sessionId;
  ImageTransmissionState? imageState;
  double? imageProgress;

  ChatMessage({
    required this.id,
    required this.messageText,
    required this.fromNodeId,
    this.fromNodeName = '',
    DateTime? timestamp,
    this.isMine = false,
    this.type = ChatMessageType.text,
    this.imageId,
    this.sessionId,
    this.imageState,
    this.imageProgress,
  }) : timestamp = timestamp ?? DateTime.now();
}

enum ImageTransmissionState {
  idle,
  preview,
  sending,
  waitingAck,
  retransmitting,
  waitingResult,
  completed,
  error,
  cancelled,
}

class MeshNode {
  final int nodeId;
  final String nodeName;
  bool isOnline;
  DateTime lastSeen;

  MeshNode({
    required this.nodeId,
    required this.nodeName,
    this.isOnline = true,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  String get nodeIdHex => '0x${nodeId.toRadixString(16).padLeft(8, '0')}';
}
