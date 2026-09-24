// lib/data/models/notification_model.dart
import '../../core/utils/helpers.dart';
import '../../core/utils/timezone.dart';

/// Emoji blocks na ginagamit ng server para i-decorate ang notification title
/// (`decorateNotificationTitle` sa `supabase/functions/_shared/notifications.ts`):
/// ⭐ ⚠️ ✅ ❌ 💰 🧾 🚚 ⏰ ⌛ 🏦 🔔 👤 ↩️ 📋 🔍 🚫 ...
final RegExp _leadingEmojiPattern = RegExp(
  r'^(?:[\u{1F000}-\u{1FAFF}\u{2190}-\u{21FF}\u{2300}-\u{23FF}'
  r'\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}\u{20E3}]+[ \u00A0]*)+',
  unicode: true,
);

/// Tinatanggal ang naka-prefix na emoji sa notification title.
///
/// BAKIT: ang title na nai-save sa DB ay may emoji prefix para agad itong
/// makilala sa FCM push / system tray. Pero sa loob ng app, ang font stack ay
/// `Inter` (tingnan ang `app_theme.dart` / `app_typography.dart`) na WALANG
/// emoji glyph, at walang color-emoji fallback ang web (CanvasKit) — kaya ang
/// emoji ay nagre-render bilang `.notdef` ng Inter: isang **manipis na
/// vertical bar** sa unahan ng title (hal. "▌Account Upgrade Submitted").
///
/// Sa app, ang per-type na colored icon sa listahan ang kumakatawan sa uri ng
/// notification, kaya hindi na kailangan ang emoji dito.
String stripNotificationEmoji(String raw) =>
    raw.replaceFirst(_leadingEmojiPattern, '').trim();

class NotificationModel {
  final String id;
  final String userId;
  final String title;
  final String body;
  final String type;
  final String? referenceId;
  final bool isRead;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    this.referenceId,
    required this.isRead,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) =>
      NotificationModel(
        id: json['id'],
        userId: json['user_id'],
        // Walang emoji prefix sa app — tingnan ang [stripNotificationEmoji].
        title: stripNotificationEmoji(json['title'] ?? ''),
        body: json['body'] ?? '',
        type: json['type'] ?? 'general',
        referenceId: json['reference_id'],
        isRead: parseBool(json['is_read'], fallback: false),
        createdAt: json['created_at'] != null
            ? parseManila(json['created_at'])!
            : DateTime.now(),
      );

  NotificationModel copyWith({bool? isRead}) => NotificationModel(
        id: id,
        userId: userId,
        title: title,
        body: body,
        type: type,
        referenceId: referenceId,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
      );
}
