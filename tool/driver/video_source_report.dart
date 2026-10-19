import 'video_clock_bounds.dart';

/// Checks every actual key, including pause/resume inputs and counter wraps.
/// The fixture logs the first draw of each sequence; it is not GPU completion.
ClockJson videoSourceReport(List<ClockJson> rounds, List<ClockJson> timeline) {
  final issues = <String>[];
  final segments = <ClockJson>[];
  final expected = <int>{};
  if (rounds.isEmpty) issues.add('No measured rounds.');
  for (final round in rounds) {
    final inputs = (round['inputs'] as List? ?? const []).cast<ClockJson>();
    if (inputs.isEmpty) issues.add('Round has no timed input evidence.');
    final pause = round['pause'] as ClockJson?;
    if (pause == null || pause['stage'] != 'complete') {
      issues.add('Round pause input incomplete.');
    }
    for (final sample in [...inputs, ?pause]) {
      final sequence = sample['fixtureSequence'];
      final counter = sample['counter'] ?? sample['expectedCounter'];
      if (sequence is! int || sequence < 1 || counter is! int) {
        issues.add('Missing fixture input identity.');
        continue;
      }
      if (!expected.add(sequence)) {
        issues.add('Repeated requested sequence $sequence.');
        continue;
      }
      final records = timeline.where((r) => r['sequence'] == sequence).toList();
      final input = records.where((r) => r['kind'] == 'input').toList();
      final draw = records.where((r) => r['kind'] == 'draw').toList();
      if (records.length != 2 ||
          input.length != 1 ||
          draw.length != 1 ||
          records.any((r) => r['counter'] != counter)) {
        issues.add('Missing or ambiguous input/draw for sequence $sequence.');
        continue;
      }
      final entered = input.single['nanoUs'];
      final start = draw.single['drawStartUs'];
      final end = draw.single['nanoUs'];
      if (entered is! int ||
          start is! int ||
          end is! int ||
          entered < 0 ||
          start < entered ||
          end < start) {
        issues.add('Reversed input/draw time for sequence $sequence.');
        continue;
      }
      segments.add({
        'sequence': sequence,
        'counter': counter,
        'inputToDrawStartUs': start - entered,
        'drawCallbackUs': end - start,
      });
    }
  }
  final initial = timeline.where(
    (r) => r['sequence'] == 0 && r['kind'] == 'draw',
  );
  if (initial.length != 1) {
    issues.add('Expected one initial draw; missing log or Activity reset.');
  }
  if (timeline.any(
    (r) =>
        (r['sequence'] == 0 && r['kind'] != 'draw') ||
        (r['sequence'] != 0 && !expected.contains(r['sequence'])),
  )) {
    issues.add('Unexpected target input sequence.');
  }
  final bounds = videoClockBounds([
    for (final round in rounds)
      {...round, 'samples': round['inputs'] ?? const <ClockJson>[]},
  ], timeline);
  return {
    'targetTimelineComplete': issues.isEmpty && segments.isNotEmpty,
    'targetTimelineIssues': issues,
    'targetDrawSegments': segments,
    // valid/complete here qualifies draw bounds. PTS compatibility remains a
    // separate conditional observation; the synthetic repeated-frame PTS of a
    // capture must never silently become a physical presentation timestamp.
    'clockBounds': bounds,
  };
}
