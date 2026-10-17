typedef ClockJson = Map<String, dynamic>;

/// Conditional clock bounds; this does not prove equal clock rates or no VM pause.
ClockJson videoClockBounds(List<ClockJson> rounds, List<ClockJson> timeline) {
  final results = <ClockJson>[];
  for (final round in rounds) {
    try {
      results.add(_roundBounds(round, timeline));
    } catch (error) {
      results.add({'round': round['round'], 'valid': false, 'error': '$error'});
    }
  }
  return {
    'model': 'constant_offset_within_round',
    'assumptions': 'No suspend, VM pause, restore, clock step or material rate difference within the round; interval overlap does not prove these conditions.',
    'ptsAssumption': 'Source PTS shares the target nanoTime origin and rate. PTS bounds are conditional on this additional assumption, not encoder duration.',
    'unit': 'us',
    'complete':
        results.isNotEmpty && results.every((row) => row['valid'] == true),
    'rounds': results,
  };
}

ClockJson _roundBounds(ClockJson round, List<ClockJson> timeline) {
  final before = (round['clockBefore'] as List).cast<ClockJson>();
  final after = (round['clockAfter'] as List).cast<ClockJson>();
  final probes = [...before, ...after];
  if (before.isEmpty || after.isEmpty) {
    throw StateError('Missing clock bracket.');
  }
  final offsets = <(int, int)>[];
  for (final probe in probes) {
    final a = probe['controllerBeforeUs'] as int;
    final b = probe['controllerAfterUs'] as int;
    final low = probe['targetBootLowerUs'] as int;
    final high = probe['targetBootUpperUs'] as int;
    if (a < 0 || b < a || low < 0 || high - low != 10000) {
      throw StateError('Invalid probe ordering or uptime quantum.');
    }
    // Expand integer microsecond truncation before intersection. Neither
    // network symmetry nor a shell-overhead correction is assumed.
    offsets.add((low - b - 1, high - a + 1));
  }
  final (offsetLow, offsetHigh) = _intersection(offsets);
  final samples = (round['samples'] as List).cast<ClockJson>();
  if (samples.isEmpty) throw StateError('No correlated samples.');
  final deltas = <(int, int)>[];
  for (final sample in samples) {
    final records = timeline
        .where((row) => row['sequence'] == sample['fixtureSequence'])
        .toList();
    if (records.length != 2 ||
        records.where((row) => row['kind'] == 'input').length != 1 ||
        records.where((row) => row['kind'] == 'draw').length != 1 ||
        records.any((row) => row['counter'] != sample['counter'])) {
      throw StateError('Missing unique input/draw clock observations.');
    }
    final input = records.singleWhere((row) => row['kind'] == 'input');
    final draw = records.singleWhere((row) => row['kind'] == 'draw');
    if ((input['nanoUs'] as int) > (draw['drawStartUs'] as int) ||
        (draw['drawStartUs'] as int) > (draw['nanoUs'] as int)) {
      throw StateError('Invalid input/draw event ordering.');
    }
    for (final record in records) {
      deltas.add(
        _bridge(
          record['nanoUs'],
          record['bootBeforeUs'],
          record['bootAfterUs'],
        ),
      );
      if (record['kind'] == 'draw') {
        deltas.add(
          _bridge(
            record['drawStartUs'],
            record['drawStartBootBeforeUs'],
            record['drawStartBootAfterUs'],
          ),
        );
      }
    }
  }
  final (deltaLow, deltaHigh) = _intersection(deltas);
  final sampleRows = <ClockJson>[];
  for (final sample in samples) {
    final raw = sample['transportFrame'] as ClockJson;
    final pts = raw['sourcePtsUs'] as int;
    final received =
        (raw['firstAdbRead'] as ClockJson)['payloadStartedUs'] as int;
    final complete = raw['readCompletedUs'] as int;
    if (received < (before.last['controllerAfterUs'] as int) ||
        complete > (after.first['controllerBeforeUs'] as int) ||
        complete < received) {
      throw StateError('Samples fall outside calibration brackets.');
    }
    // B = N + delta and B = H + offset. Preserve both ends and allow
    // microsecond truncation of the observed PTS and receipt clock.
    final lower = received - pts + offsetLow - deltaHigh - 1;
    final upper = received - pts + offsetHigh - deltaLow + 1;
    final draw = timeline.singleWhere(
      (row) =>
          row['sequence'] == sample['fixtureSequence'] && row['kind'] == 'draw',
    );
    final drawEnd = draw['nanoUs'] as int;
    sampleRows.add({
      'fixtureSequence': sample['fixtureSequence'],
      'sourcePtsUs': pts,
      'ptsCompatible': upper >= 0,
      'sourceToPayloadLowerUs': lower,
      'sourceToPayloadUpperUs': upper,
      'sourceToRawCompleteLowerUs': complete - pts + offsetLow - deltaHigh - 1,
      'sourceToRawCompleteUpperUs': complete - pts + offsetHigh - deltaLow + 1,
      'drawEndToPayloadLowerUs': received - drawEnd + offsetLow - deltaHigh - 1,
      'drawEndToPayloadUpperUs': received - drawEnd + offsetHigh - deltaLow + 1,
    });
  }
  return {
    'round': round['round'],
    'valid': true,
    'offsetLowerUs': offsetLow,
    'offsetUpperUs': offsetHigh,
    'bootMinusMonoLowerUs': deltaLow,
    'bootMinusMonoUpperUs': deltaHigh,
    'intervalWidthUs': offsetHigh - offsetLow + deltaHigh - deltaLow + 2,
    'samples': sampleRows,
  };
}

(int, int) _bridge(dynamic nano, dynamic before, dynamic after) {
  final n = nano as int, a = before as int, b = after as int;
  if (n < 0 || a < 0 || b < a) {
    throw StateError('Invalid target dual clock bracket.');
  }
  return (a - n - 1, b - n + 1);
}

(int, int) _intersection(List<(int, int)> values) {
  var (low, high) = values.first;
  for (final (a, b) in values.skip(1)) {
    if (a > low) low = a;
    if (b < high) high = b;
  }
  if (low > high) throw StateError('Clock intervals do not overlap.');
  return (low, high);
}
