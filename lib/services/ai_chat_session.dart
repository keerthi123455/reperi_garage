/// Keeps the REPERI AI conversation alive across opens within the same app
/// session — closing the chat (the X button) or navigating away to a
/// suggested package and coming back no longer starts the conversation
/// over. `AiAdvisorSheet` reads and mutates this same List directly, so
/// there's no separate "save" step: every message it appends is already
/// written here.
///
/// Session-scoped only (cleared on sign-out, see [clear]) — it does not
/// survive an app restart, since there's nowhere else to persist it.
class AiChatSession {
  AiChatSession._();

  static final List<Map<String, dynamic>> messages = [];

  static void clear() => messages.clear();
}
