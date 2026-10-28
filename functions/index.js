const functions = require("firebase-functions");
const admin = require("firebase-admin");
const cors = require("cors")({ origin: true });

// Initialize Firebase Admin SDK
admin.initializeApp();

/**
 * HTTPS Cloud Function: sendNotification
 * 
 * Secure backend endpoint to send push notifications via Firebase Cloud Messaging (FCM).
 * This keeps all server credentials, service accounts, and private keys secure on the server.
 * 
 * Expected JSON payload:
 * {
 *   "receiverToken": "fcm_device_token_of_mobile_b",
 *   "title": "Hello",
 *   "body": "How are you?",
 *   "senderName": "Mobile A",
 *   "senderId": "user_123"
 * }
 */
exports.sendNotification = functions.https.onRequest((req, res) => {
  return cors(req, res, async () => {
    // Only accept POST requests
    if (req.method !== "POST") {
      return res.status(405).json({
        success: false,
        message: "Method Not Allowed. Please send a POST request.",
      });
    }

    try {
      const { receiverToken, title, body, senderName, senderId } = req.body;

      // 1. Validate required fields
      if (!receiverToken || typeof receiverToken !== "string" || receiverToken.trim() === "") {
        return res.status(400).json({
          success: false,
          message: "Validation Error: 'receiverToken' is required and must be a valid FCM token string.",
        });
      }

      if (!title || typeof title !== "string" || title.trim() === "") {
        return res.status(400).json({
          success: false,
          message: "Validation Error: 'title' is required.",
        });
      }

      if (!body || typeof body !== "string" || body.trim() === "") {
        return res.status(400).json({
          success: false,
          message: "Validation Error: 'body' is required.",
        });
      }

      // 2. Prepare FCM Message Payload (HTTP v1 Standard)
      const message = {
        token: receiverToken.trim(),
        notification: {
          title: title.trim(),
          body: body.trim(),
        },
        data: {
          title: title.trim(),
          body: body.trim(),
          senderName: (senderName && typeof senderName === "string") ? senderName.trim() : "Unknown Sender",
          senderId: (senderId && typeof senderId === "string") ? senderId.trim() : "",
          click_action: "FLUTTER_NOTIFICATION_CLICK",
          sentAt: new Date().toISOString(),
        },
        android: {
          priority: "high",
          notification: {
            channelId: "high_importance_channel",
            sound: "default",
            defaultSound: true,
            defaultVibrateTimings: true,
            priority: "max",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              badge: 1,
            },
          },
        },
      };

      // 3. Send Notification via Firebase Admin SDK
      const response = await admin.messaging().send(message);

      console.log(`✅ Push notification sent successfully to token [${receiverToken.substring(0, 15)}...]: MessageId = ${response}`);

      // 4. Return success response
      return res.status(200).json({
        success: true,
        message: "Notification sent successfully via FCM!",
        messageId: response,
      });

    } catch (error) {
      console.error("❌ Error sending FCM push notification:", error);

      // Handle invalid or expired FCM registration tokens
      if (
        error.code === "messaging/registration-token-not-registered" ||
        error.code === "messaging/invalid-registration-token"
      ) {
        return res.status(404).json({
          success: false,
          code: error.code,
          message: "The target receiver's FCM token is invalid or has expired.",
        });
      }

      return res.status(500).json({
        success: false,
        code: error.code || "unknown_error",
        message: `Failed to deliver notification: ${error.message}`,
      });
    }
  });
});
