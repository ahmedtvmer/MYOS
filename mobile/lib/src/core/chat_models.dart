// Hosted player-assistant chat models (ADR 016/036).

import 'models.dart';

/// One persisted turn in the player's chat history (`GET /chat/history`).
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.createdAt,
    this.kind = 'message',
    this.requestSuggestion,
    this.programEditPreview,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: _string(json['id']),
        role: _string(json['role']),
        content: _string(json['content']),
        createdAt:
            json['created_at'] is String ? json['created_at'] as String : null,
        kind: json['kind'] is String ? json['kind'] as String : 'message',
        programEditPreview: json['program_edit_preview'] is Map<String, dynamic>
            ? json['program_edit_preview'] as Map<String, dynamic>
            : null,
      );

  final String id;
  final String role;
  final String content;
  final String? createdAt;

  /// The server's classification of this message: `debrief` for a
  /// session-logged pointer written at workout commit (ADR 033/036), else
  /// `message`. The client never re-derives it from the wording.
  final String kind;

  /// A transient action from this streamed reply; never part of stored history.
  final ProgramRequestDraft? requestSuggestion;
  final Map<String, dynamic>? programEditPreview;

  bool get isUser => role == 'user';

  /// A session-commit pointer written at workout commit (ADR 033). Rendered as
  /// a distinct debrief card rather than a normal assistant bubble.
  bool get isDebriefPointer => kind == 'debrief';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'role': role,
        'content': content,
        if (createdAt != null) 'created_at': createdAt,
        'kind': kind,
        if (programEditPreview != null)
          'program_edit_preview': programEditPreview,
      };

  static String _string(dynamic value) => value is String ? value : '';
}

/// One event decoded from the `POST /chat/messages` SSE stream.
sealed class ChatStreamEvent {
  const ChatStreamEvent();
}

/// A streamed assistant token chunk; append it to the live draft.
class ChatToken extends ChatStreamEvent {
  const ChatToken(this.token);

  final String token;
}

/// A transient server status while a read-only player tool is running.
class ChatStatus extends ChatStreamEvent {
  const ChatStatus(this.status);

  final String status;
}

/// The turn finished: the reply is final and may have changed the program.
class ChatDone extends ChatStreamEvent {
  const ChatDone({
    required this.responseContent,
    required this.programUpdated,
    this.movementRestrictionsUpdated = false,
    this.outcome = 'completed',
    this.lifterAllowance,
    this.coachAllowance,
    this.requestSuggestion,
    this.programEditPreview,
  });

  final String responseContent;
  final bool programUpdated;
  final bool movementRestrictionsUpdated;
  final String outcome;
  final AiAllowance? lifterAllowance;
  final AiAllowance? coachAllowance;
  final ProgramRequestDraft? requestSuggestion;
  final Map<String, dynamic>? programEditPreview;
}

/// The turn failed; [detail] is the service's fixed, non-leaking message.
class ChatError extends ChatStreamEvent {
  const ChatError(
    this.detail, {
    this.messageCode,
    this.messageParams,
    this.messageFallback,
  });

  final String detail;
  final String? messageCode;
  final Map<String, dynamic>? messageParams;
  final String? messageFallback;
}
