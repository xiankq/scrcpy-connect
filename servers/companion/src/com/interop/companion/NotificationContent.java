package com.interop.companion;

import android.app.Notification;
import android.os.Bundle;

/** 原通知提供的纯文本，包含展开样式。 */
final class NotificationContent {
    private NotificationContent() {}

    private static String bounded(CharSequence value, int limit) {
        if (value == null) return "";
        String text = value.toString();
        return text.length() > limit ? text.substring(0, limit) : text;
    }

    static String title(Bundle extras) {
        if (extras == null) return "";
        String expanded = bounded(extras.getCharSequence(Notification.EXTRA_TITLE_BIG), 4096);
        return expanded.isEmpty()
            ? bounded(extras.getCharSequence(Notification.EXTRA_TITLE), 4096) : expanded;
    }

    static String body(Bundle extras) {
        if (extras == null) return "";
        String expanded = bounded(extras.getCharSequence(Notification.EXTRA_BIG_TEXT), 16384);
        if (!expanded.isEmpty()) return expanded;
        CharSequence[] lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES);
        if (lines != null && lines.length > 0) {
            StringBuilder text = new StringBuilder();
            for (CharSequence line : lines) {
                if (line == null || line.length() == 0) continue;
                if (text.length() > 0) text.append('\n');
                text.append(bounded(line, 16384 - text.length()));
                if (text.length() >= 16384) break;
            }
            if (text.length() > 0) return text.toString();
        }
        // MessagingStyle 通过 EXTRA_TITLE/EXTRA_TEXT 提供当前会话预览，保留系统提供的归因。
        //
        return bounded(extras.getCharSequence(Notification.EXTRA_TEXT), 16384);
    }
}
