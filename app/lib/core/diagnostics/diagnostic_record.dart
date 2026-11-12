enum LogLevel { info, warning, error }

enum DiagnosticArea { app, connection, video, audio, runtime }

class DiagnosticRecord {
  const DiagnosticRecord({
    required this.time,
    required this.level,
    required this.area,
    required this.event,
    required this.fields,
  });

  final DateTime time;
  final LogLevel level;
  final DiagnosticArea area;
  final String event;
  final Map<String, Object?> fields;

  Map<String, Object?> toJson() => {
    'time': time.toUtc().toIso8601String(),
    'level': level.name,
    'area': area.name,
    'event': event,
    'fields': fields,
  };
}
