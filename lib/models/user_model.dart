import 'package:cloud_firestore/cloud_firestore.dart';

/// Model representing an App User in Cloud Firestore.
class AppUser {
  final String userId;
  final String name;
  final String fcmToken;
  final String platform;
  final DateTime? updatedAt;

  const AppUser({
    required this.userId,
    required this.name,
    required this.fcmToken,
    required this.platform,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'fcmToken': fcmToken,
      'platform': platform,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    DateTime? updated;
    if (data['updatedAt'] != null && data['updatedAt'] is Timestamp) {
      updated = (data['updatedAt'] as Timestamp).toDate();
    }

    return AppUser(
      userId: data['userId']?.toString() ?? doc.id,
      name: data['name']?.toString() ?? 'Unknown User',
      fcmToken: data['fcmToken']?.toString() ?? '',
      platform: data['platform']?.toString() ?? 'Mobile',
      updatedAt: updated,
    );
  }
}
