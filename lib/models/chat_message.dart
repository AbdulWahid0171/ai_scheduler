class ChatMessage {
  final int? id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final String? metadata; // For storing JSON results or summary info

  ChatMessage({
    this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.metadata,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'text': text,
      'is_user': isUser ? 1 : 0,
      'timestamp': timestamp.toIso8601String(),
      'metadata': metadata,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as int?,
      text: map['text'] as String,
      isUser: (map['is_user'] as int) == 1,
      timestamp: DateTime.parse(map['timestamp'] as String),
      metadata: map['metadata'] as String?,
    );
  }
}
