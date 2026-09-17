import '../db/call_db.dart';

abstract class CallPersistence {
  Future<void> saveCall(Map<String, dynamic> call);

  Future<Map<String, dynamic>?> getCall(String sessionId);

  Future<Map<String, dynamic>?> getCallByAudioPath(String audioPath);

  Future<void> updateStatus(String sessionId, String status);

  Future<void> deleteCalls(
    Iterable<String> sessionIds, {
    Iterable<String> audioPaths = const [],
  }) async {}

  Future<List<Map<String, dynamic>>> getAllCalls() async => const [];
}

class CallRepository implements CallPersistence {
  final db = CallDatabase.instance;

  @override
  Future<void> saveCall(Map<String, dynamic> call) async {
    await db.insertCall(call);
  }

  @override
  Future<List<Map<String, dynamic>>> getAllCalls() async {
    return await db.getAllCalls();
  }

  Future<List<Map<String, dynamic>>> getPendingCalls() async {
    return await db.getPendingCalls();
  }

  @override
  Future<Map<String, dynamic>?> getCall(String sessionId) {
    return db.getCallBySessionId(sessionId);
  }

  @override
  Future<Map<String, dynamic>?> getCallByAudioPath(String audioPath) {
    return db.getCallByAudioPath(audioPath);
  }

  @override
  Future<void> updateStatus(String sessionId, String status) async {
    await db.updateCallStatus(sessionId, status);
  }

  @override
  Future<void> deleteCalls(
    Iterable<String> sessionIds, {
    Iterable<String> audioPaths = const [],
  }) async {
    await db.deleteCalls(sessionIds: sessionIds, audioPaths: audioPaths);
  }
}
