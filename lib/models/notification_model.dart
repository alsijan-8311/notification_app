/// Model representing a push notification with read/unread tracking.
class NotificationModel {
  final String id;
  final String title;
  final String body;
  final DateTime receivedAt;
  final bool isRead;
  final String? senderName;
  final String type; // 'foreground', 'click_background', 'click_terminated'
  final Map<String, dynamic>? data;

  const NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.receivedAt,
    this.isRead = false,
    this.senderName,
    this.type = 'foreground',
    this.data,
  });

  /// Creates a copy with optional updated fields
  NotificationModel copyWith({
    String? id,
    String? title,
    String? body,
    DateTime? receivedAt,
    bool? isRead,
    String? senderName,
    String? type,
    Map<String, dynamic>? data,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      receivedAt: receivedAt ?? this.receivedAt,
      isRead: isRead ?? this.isRead,
      senderName: senderName ?? this.senderName,
      type: type ?? this.type,
      data: data ?? this.data,
    );
  }

  /// Converts model to Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'receivedAt': receivedAt.toIso8601String(),
      'isRead': isRead,
      'senderName': senderName,
      'type': type,
      'data': data,
    };
  }

  /// Factory constructor from Map
  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    return NotificationModel(
      id: map['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: map['title']?.toString() ?? 'No Title',
      body: map['body']?.toString() ?? 'No Message',
      receivedAt: map['receivedAt'] != null
          ? (map['receivedAt'] is DateTime
              ? map['receivedAt'] as DateTime
              : DateTime.tryParse(map['receivedAt'].toString()) ?? DateTime.now())
          : DateTime.now(),
      isRead: map['isRead'] as bool? ?? false,
      senderName: map['senderName']?.toString(),
      type: map['type']?.toString() ?? 'foreground',
      data: map['data'] is Map<String, dynamic> ? map['data'] as Map<String, dynamic> : null,
    );
  }
}
