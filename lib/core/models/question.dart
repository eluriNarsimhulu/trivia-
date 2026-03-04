/// Immutable model for a single trivia question.
///
/// Architecture note:
///   QuestionType drives two things:
///     1. Which UI widget the question screen renders (Stage 5).
///     2. How the REST answer payload is validated (Stage 6).
///   Neither concern leaks into this model — it is pure data.

enum QuestionType {
  multipleChoice,
  trueFalse,
  typeIn,
  imageBased,
}

class Question {
  final String id;
  final QuestionType type;
  final String text;
  final List<String> options;  // empty for typeIn
  final String? imageUrl;      // non-null only for imageBased
  final int timerSeconds;

  const Question({
    required this.id,
    required this.type,
    required this.text,
    required this.options,
    required this.timerSeconds,
    this.imageUrl,
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      id:           json['id'] as String,
      type:         _parseType(json['type'] as String),
      text:         json['text'] as String,
      options:      List<String>.unmodifiable(
                      json['options'] as List? ?? [],
                    ),
      timerSeconds: json['timer_seconds'] as int,
      imageUrl:     json['image_url'] as String?,
    );
  }

  static QuestionType _parseType(String raw) {
    const map = {
      'mcq':         QuestionType.multipleChoice,
      'true_false':  QuestionType.trueFalse,
      'type_in':     QuestionType.typeIn,
      'image_based': QuestionType.imageBased,
    };
    final type = map[raw];
    if (type == null) throw ArgumentError('Unknown question type: $raw');
    return type;
  }
}