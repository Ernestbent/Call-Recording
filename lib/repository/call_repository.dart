import '../db/call_db.dart';

class CallRepository {
  final db = CallDatabase.instance;

  Future<void> saveCall(Map<String, dynamic> call) async {
    await db.insertCall(call);
  }

  Future<List<Map<String, dynamic>>> getAllCalls() async {
    return await db.getAllCalls();
  }

  Future<List<Map<String, dynamic>>> getPendingCalls() async {
    return await db.getPendingCalls();
  }

  Future<void> updateStatus(String sessionId, String status) async {
    await db.updateCallStatus(sessionId, status);
  }
}
