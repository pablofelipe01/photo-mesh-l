class SessionMessage {
  final String text;
  final bool isQuestion;
  final DateTime timestamp;

  SessionMessage({
    required this.text,
    required this.isQuestion,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class ConsultaSession {
  final String sessionId;
  final String imageId;
  int questionCount;
  bool isActive;
  final DateTime createdAt;
  final List<SessionMessage> messages;

  static const int maxQuestions = 5;

  ConsultaSession({
    required this.sessionId,
    required this.imageId,
    this.questionCount = 0,
    this.isActive = true,
    DateTime? createdAt,
    List<SessionMessage>? messages,
  })  : createdAt = createdAt ?? DateTime.now(),
        messages = messages ?? [];

  bool get canAskMore => isActive && questionCount < maxQuestions;
}
