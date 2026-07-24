import '../db/call_db.dart';

abstract class CallPersistence {
  Future<void> saveCall(Map<String, dynamic> call);

  Future<Map<String, dynamic>?> getCall(String sessionId);

  Future<void> updateStatus(String sessionId, String status);
}

class CallRepository implements CallPersistence {
  final db = CallDatabase.instance;

  @override
  Future<void> saveCall(Map<String, dynamic> call) async {
    await db.insertCall(call);
  }

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
  Future<void> updateStatus(String sessionId, String status) async {
    await db.updateCallStatus(sessionId, status);
  }
}
