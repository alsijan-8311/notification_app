import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_model.dart';
import '../pages/notification_details_page.dart';

/// Top-level background message handler for Firebase Cloud Messaging (FCM).
///
/// MUST be a top-level function annotated with `@pragma('vm:entry-point')`
/// so Flutter can execute it in an isolated background thread when the app
/// is minimized or completely closed (terminated).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized in this isolated background context
  await Firebase.initializeApp();

  debugPrint('==================================================');
  debugPrint('📥 [FCM Background Message Received]');
  debugPrint('Notification Title: ${message.notification?.title ?? message.data['title']}');
  debugPrint('Notification Body: ${message.notification?.body ?? message.data['body']}');
  debugPrint('Message ID: ${message.messageId}');
  debugPrint('Data Payload: ${message.data}');
  debugPrint('==================================================');
}

/// Global navigator key for notification click navigation across all app states
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Service class responsible for all push notification operations:
/// - Requesting Android 13+ & iOS notification permissions
/// - Configuring local notifications for foreground popups
/// - Generating and refreshing FCM device registration token
/// - Automatically uploading and syncing device token with Cloud Firestore
/// - Managing local user identity (userId & name)
/// - Handling foreground, background, and terminated notification clicks
/// - Sending push notifications to other devices securely via Backend Cloud Function
class NotificationService {
  // Singleton pattern
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  bool get isFirebaseReady => Firebase.apps.isNotEmpty;
  FirebaseMessaging? get _fcm => isFirebaseReady ? FirebaseMessaging.instance : null;
  FirebaseFirestore? get _firestore => isFirebaseReady ? FirebaseFirestore.instance : null;
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// Notification Channel details for Android heads-up alerts
  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    'high_importance_channel', // id
    'High Importance Notifications', // title
    description: 'This channel is used for important push notifications.',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  /// Cached device token for UI display
  String? _deviceToken;
  String? get deviceToken => _deviceToken;

  /// Current user details
  String _userId = '';
  String _userName = 'My Mobile Device';
  String get userId => _userId;
  String get userName => _userName;

  /// Backend Cloud Function URL for sending push notifications
  /// Users can configure this in settings or default to their deployed Firebase Cloud Function URL
  String _cloudFunctionUrl = '';
  String get cloudFunctionUrl => _cloudFunctionUrl;

  /// Stream to notify UI when a notification arrives or is clicked
  final StreamController<NotificationModel> _notificationStream =
      StreamController<NotificationModel>.broadcast();
  Stream<NotificationModel> get notificationStream => _notificationStream.stream;

  /// Pending notification received from terminated state (to open after UI is mounted)
  NotificationModel? _pendingTerminatedNotification;
  NotificationModel? get pendingTerminatedNotification => _pendingTerminatedNotification;

  /// Clears pending notification once handled
  void clearPendingTerminatedNotification() {
    _pendingTerminatedNotification = null;
  }

  /// Initializes all notification services safely
  Future<void> initialize() async {
    // 0. Load or generate user profile from SharedPreferences
    await _loadUserSession();

    // 1. Initialize Flutter Local Notifications for foreground popups
    await _initLocalNotifications();

    if (!isFirebaseReady) {
      debugPrint(
          '⚠️ NotificationService: Firebase is not initialized. Please ensure google-services.json is present in android/app/.');
      return;
    }

    // 2. Request notification permissions (Android 13+ POST_NOTIFICATIONS & iOS)
    await requestNotificationPermission();

    // 3. Setup foreground notification listener
    _setupForegroundListener();

    // 4. Setup background notification click listener (when app is minimized)
    _setupBackgroundClickListener();

    // 5. Check if app was opened from a completely terminated state by tapping a notification
    await checkTerminatedNotification();

    // 6. Generate device token and upload to Cloud Firestore
    await getAndSaveDeviceToken();

    // 7. Listen for token refresh events
    _fcm?.onTokenRefresh.listen((String newToken) async {
      _deviceToken = newToken;
      debugPrint('🔄 Firebase Device Token Refreshed: $newToken');
      await syncUserToFirestore(name: _userName, customToken: newToken);
    });
  }

  /// Loads locally saved user ID and name
  Future<void> _loadUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('user_id') ?? '';
    _userName = prefs.getString('user_name') ?? '';
    _cloudFunctionUrl = prefs.getString('cloud_function_url') ?? '';

    if (_userId.isEmpty) {
      // Generate a clean stable ID for this device
      _userId = 'user_${DateTime.now().millisecondsSinceEpoch}_${(100 + (DateTime.now().microsecond % 900))}';
      await prefs.setString('user_id', _userId);
    }

    if (_userName.isEmpty) {
      _userName = 'Mobile ${Platform.isAndroid ? 'Android' : 'User'}';
      await prefs.setString('user_name', _userName);
    }
  }

  /// Updates the current user's display name and syncs with Firestore
  Future<void> updateUserName(String newName) async {
    if (newName.trim().isEmpty) return;
    _userName = newName.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', _userName);

    // Sync with Firestore
    await syncUserToFirestore(name: _userName);
  }

  /// Updates the Cloud Function URL
  Future<void> updateCloudFunctionUrl(String url) async {
    _cloudFunctionUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cloud_function_url', _cloudFunctionUrl);
  }

  /// Requests user permission to display alerts, badge, and sound.
  Future<void> requestNotificationPermission() async {
    if (_fcm == null) return;
    try {
      NotificationSettings settings = await _fcm!.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('✅ Notification Permission: Authorized');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        debugPrint('⚠️ Notification Permission: Provisional');
      } else {
        debugPrint('❌ Notification Permission: Denied or Not Determined');
      }
    } catch (e) {
      debugPrint('⚠️ Error requesting notification permission: $e');
    }
  }

  /// Sets up Flutter Local Notifications for foreground heads-up display
  Future<void> _initLocalNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotificationsPlugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('👆 Local Notification Tapped: ${response.payload}');
        try {
          Map<String, dynamic> data = {};
          if (response.payload != null && response.payload!.isNotEmpty) {
            data = jsonDecode(response.payload!);
          }
          final model = NotificationModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: data['title']?.toString() ?? 'Opened from Notification',
            body: data['body']?.toString() ?? (response.payload ?? 'No message body'),
            receivedAt: DateTime.now(),
            isRead: true,
            type: 'foreground_tap',
            data: data,
          );
          _navigateToDetailsPage(model);
        } catch (_) {
          final model = NotificationModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: 'Notification Alert',
            body: response.payload ?? '',
            receivedAt: DateTime.now(),
            isRead: true,
            type: 'foreground_tap',
          );
          _navigateToDetailsPage(model);
        }
      },
    );

    // Create the High Importance Notification Channel on Android
    await _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);
  }

  /// Generates the FCM Device Token, logs it to console, and saves it to Firestore
  Future<String?> getAndSaveDeviceToken() async {
    if (_fcm == null) {
      debugPrint('ℹ️ FCM token unavailable: Firebase is not initialized.');
      return null;
    }
    try {
      _deviceToken = await _fcm!.getToken();

      debugPrint('==================================================');
      debugPrint('🔥 Firebase Device Token:');
      debugPrint('$_deviceToken');
      debugPrint('==================================================');

      if (_deviceToken != null && _deviceToken!.isNotEmpty) {
        await syncUserToFirestore(name: _userName, customToken: _deviceToken);
      }

      return _deviceToken;
    } catch (e) {
      debugPrint('⚠️ Error fetching FCM device token: $e');
      return null;
    }
  }

  /// Uploads or updates the current device user in Cloud Firestore:
  /// users -> [userId] -> { userId, name, fcmToken, platform, updatedAt }
  Future<void> syncUserToFirestore({String? name, String? customToken}) async {
    if (_firestore == null) return;
    final token = customToken ?? _deviceToken;
    if (token == null || token.isEmpty) return;

    try {
      final docId = _userId.isNotEmpty ? _userId : 'user_${token.hashCode.abs()}';

      final Map<String, dynamic> userData = {
        'userId': docId,
        'name': (name != null && name.trim().isNotEmpty) ? name.trim() : _userName,
        'fcmToken': token,
        'platform': Platform.isAndroid ? 'Android' : (Platform.isIOS ? 'iOS' : 'Other'),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Set with merge: true ensures we replace/update without losing other fields
      await _firestore!
          .collection('users')
          .doc(docId)
          .set(userData, SetOptions(merge: true))
          .timeout(const Duration(seconds: 6));

      debugPrint('☁️ User profile & token saved to Firestore: users/$docId ($name)');
    } on TimeoutException {
      debugPrint('ℹ️ Firestore sync timed out. Make sure Cloud Firestore is enabled in Firebase Console.');
    } catch (e) {
      debugPrint('ℹ️ Cloud Firestore Note: Token save error ($e). Verify Firestore security rules.');
    }
  }

  /// Handles foreground notification arrival:
  /// 1. Prints to debug console
  /// 2. Displays a heads-up local notification
  /// 3. Broadcasts to UI
  void _setupForegroundListener() {
    if (!isFirebaseReady) return;
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final String title = message.notification?.title ??
          message.data['title']?.toString() ??
          'New Notification';
      final String body = message.notification?.body ??
          message.data['body']?.toString() ??
          'You have received a new notification.';
      final String? sender = message.data['senderName']?.toString();

      debugPrint('==================================================');
      debugPrint('📩 [Foreground Notification Received]');
      debugPrint('Title: $title');
      debugPrint('Body: $body');
      debugPrint('Sender: $sender');
      debugPrint('Data: ${message.data}');
      debugPrint('==================================================');

      final notificationModel = NotificationModel(
        id: message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        body: body,
        receivedAt: DateTime.now(),
        isRead: false,
        senderName: sender,
        type: 'foreground',
        data: message.data,
      );

      // Show local heads-up notification with payload
      _showLocalNotification(
        id: message.hashCode,
        title: title,
        body: body,
        payload: jsonEncode({
          'title': title,
          'body': body,
          'senderName': sender,
          'data': message.data,
        }),
      );

      // Broadcast to UI
      _notificationStream.add(notificationModel);
    });
  }

  /// Displays local notification on device screen
  Future<void> _showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      _androidChannel.id,
      _androidChannel.name,
      channelDescription: _androidChannel.description,
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: true,
    );

    final NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _localNotificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: platformDetails,
      payload: payload,
    );
  }

  /// Handles notification tap when app was minimized in BACKGROUND
  void _setupBackgroundClickListener() {
    if (!isFirebaseReady) return;
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final String title = message.notification?.title ??
          message.data['title']?.toString() ??
          'Notification Clicked';
      final String body = message.notification?.body ??
          message.data['body']?.toString() ??
          'Opened from Background notification.';
      final String? sender = message.data['senderName']?.toString();

      debugPrint('👆 [Notification Clicked in Background]: $title');

      final notificationModel = NotificationModel(
        id: message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        body: body,
        receivedAt: DateTime.now(),
        isRead: true,
        senderName: sender,
        type: 'click_background',
        data: message.data,
      );

      _notificationStream.add(notificationModel);
      _navigateToDetailsPage(notificationModel);
    });
  }

  /// Handles notification tap when app was completely CLOSED / TERMINATED
  Future<void> checkTerminatedNotification() async {
    if (_fcm == null) return;
    RemoteMessage? initialMessage = await _fcm!.getInitialMessage();

    if (initialMessage != null) {
      final String title = initialMessage.notification?.title ??
          initialMessage.data['title']?.toString() ??
          'Terminated Notification';
      final String body = initialMessage.notification?.body ??
          initialMessage.data['body']?.toString() ??
          'App launched from closed state.';
      final String? sender = initialMessage.data['senderName']?.toString();

      debugPrint('🚀 [App Launched from Notification (Terminated State)]: $title');

      final notificationModel = NotificationModel(
        id: initialMessage.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        body: body,
        receivedAt: DateTime.now(),
        isRead: true,
        senderName: sender,
        type: 'click_terminated',
        data: initialMessage.data,
      );

      _pendingTerminatedNotification = notificationModel;
      _notificationStream.add(notificationModel);
    }
  }

  /// Helper to safely navigate to NotificationDetailsPage
  void _navigateToDetailsPage(NotificationModel model) {
    if (navigatorKey.currentState != null) {
      navigatorKey.currentState!.push(
        MaterialPageRoute(
          builder: (context) => NotificationDetailsPage(notification: model),
        ),
      );
    }
  }

  /// Sends a push notification to another mobile device via Secure Backend / Cloud Function
  ///
  /// Important security note: No FCM server key or private service account credentials
  /// are included here. The request is dispatched to the backend, which holds credentials.
  Future<Map<String, dynamic>> sendPushNotification({
    required String receiverToken,
    required String title,
    required String body,
    String? senderName,
    String? backendUrl,
  }) async {
    final String targetUrl = (backendUrl != null && backendUrl.trim().isNotEmpty)
        ? backendUrl.trim()
        : _cloudFunctionUrl;

    if (receiverToken.trim().isEmpty) {
      return {
        'success': false,
        'message': 'Receiver device token is required.',
      };
    }

    if (targetUrl.isEmpty) {
      return {
        'success': false,
        'message': 'Cloud Function URL is not configured. Please deploy the function and set the URL.',
      };
    }

    try {
      final response = await http
          .post(
            Uri.parse(targetUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'receiverToken': receiverToken.trim(),
              'title': title.trim(),
              'body': body.trim(),
              'senderName': senderName ?? _userName,
              'senderId': _userId,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        dynamic responseData;
        try {
          responseData = jsonDecode(response.body);
        } catch (_) {
          responseData = response.body;
        }

        return {
          'success': true,
          'message': 'Notification sent successfully!',
          'data': responseData,
        };
      } else {
        return {
          'success': false,
          'message': 'Server error (${response.statusCode}): ${response.body}',
        };
      }
    } on SocketException {
      return {
        'success': false,
        'message': 'No internet connection or cannot reach Cloud Function server.',
      };
    } on TimeoutException {
      return {
        'success': false,
        'message': 'Request timed out while connecting to Cloud Function.',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to send notification: $e',
      };
    }
  }

  /// Dispose resources
  void dispose() {
    _notificationStream.close();
  }
}
