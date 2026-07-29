import 'package:matrix/matrix.dart' as matrix;

extension UserNotes on matrix.Client {
  String? getUserNote(String userId) {
    final key = 'xyz.extera.user_note.$userId';
    if (!accountData.containsKey(key)) {
      return null;
    }
    final event = accountData.tryGet<matrix.BasicEvent>(key)!;
    return event.content.tryGet<String>("note");
  }

  Future<void> setUserNote(String userId, String note) async {
    final key = 'xyz.extera.user_note.$userId';
    await setAccountData(userID!, key, {"note": note});
  }
}
