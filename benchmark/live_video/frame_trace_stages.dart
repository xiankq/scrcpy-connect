/// Joins a verified snapshot to its own decoded callback and relay packet.
/// PTS identifies frames; it is never subtracted from a host timestamp. Missing
/// early callbacks and ambiguous identities stay explicit in startup evidence.
Map<String, dynamic> frameTraceStages(
  Map<String, dynamic>? native,
  List<Map<String, dynamic>> relay,
) {
  final result = <String, dynamic>{'complete': false};
  Map<String, dynamic> missing(String reason) => result..['unmatched'] = reason;
  if (native == null) return missing('native_trace_missing');
  final snapshot = native['snapshot'] as Map<String, dynamic>?;
  if (snapshot == null) return missing('snapshot_missing');
  final pts = snapshot['ptsSeconds'] as num;
  if (!pts.isFinite) return missing('snapshot_pts_nonfinite');
  result['ptsSeconds'] = pts;
  final elapsed = snapshot['elapsedUs'] as int;
  final submitted = snapshot['submittedElapsedUs'] as int;
  if (submitted < 0 || elapsed < submitted) {
    return missing('snapshot_time_reversed');
  }
  result['snapshotRequestToCallbackUs'] = elapsed - submitted;
  final decoded = (native['decoded'] as List)
      .cast<Map<String, dynamic>>()
      .where((f) => ((f['ptsSeconds'] as num) - pts).abs() < .000001)
      .toList();
  final packets = relay
      .where((f) => ((f['ptsUs'] as num) - pts * 1000000).abs() <= 1.1)
      .toList();
  result.addAll({
    'decodedMatchCount': decoded.length,
    'relayMatchCount': packets.length,
  });
  if (decoded.length != 1 || packets.length != 1) {
    return missing('frame_identity_not_unique');
  }
  final decodedUs = decoded.single['elapsedUs'] as int;
  final origin = native['clockOriginUs'] as int;
  final writeStartedUs = packets.single['writeStartedUs'] as int;
  if (decodedUs < 0 ||
      origin < 0 ||
      writeStartedUs < 0 ||
      elapsed < decodedUs ||
      origin + decodedUs < writeStartedUs) {
    return missing('frame_time_reversed');
  }
  return result..addAll({
    'complete': true,
    'relayFrame': packets.single,
    'relayToOnVideoUs': origin + decodedUs - writeStartedUs,
    'onVideoToSnapshotUs': elapsed - decodedUs,
  });
}
