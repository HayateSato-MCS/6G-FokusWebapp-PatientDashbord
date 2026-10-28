import 'package:flutter/material.dart';

/// Colours used by the fall detection widgets. Replace freely when integrating.
abstract final class FallColors {
  static const pageBackground = Color(0xFFF4F6F8);
  static const textPrimary = Color(0xFF111827);
  static const textMuted = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
  static const primary = Color(0xFF2563EB);

  static const connected = Color(0xFF059669);
  static const disconnected = Color(0xFFB91C1C);

  // pending: possible fall, waiting for the patient
  static const pendingCard = Color(0xFFFEF2F2);
  static const pendingBorder = Color(0xFFFCA5A5);
  static const pendingNotice = Color(0xFFFEE2E2);
  static const pendingNoticeText = Color(0xFF991B1B);

  // alert: caregiver must act
  static const alertNotice = Color(0xFFDC2626);
  static const alertNoticeText = Colors.white;
  static const alertBorder = Color(0xFFDC2626);
  static const alertOverlay = Color(0xFFFEF2F2);
  static const alertOverlayText = Color(0xFFDC2626);

  // resolved: patient dismissed it
  static const resolvedCard = Color(0xFFF0FDF4);
  static const resolvedBorder = Color(0xFF86EFAC);
  static const resolvedNotice = Color(0xFFDCFCE7);
  static const resolvedNoticeText = Color(0xFF166534);

  // history table tags
  static const tagYes = Color(0xFFD1FAE5);
  static const tagYesText = Color(0xFF065F46);
  static const tagNo = Color(0xFFFEE2E2);
  static const tagNoText = Color(0xFF991B1B);
  static const tagPending = Color(0xFFFEF3C7);
  static const tagPendingText = Color(0xFF92400E);
}
