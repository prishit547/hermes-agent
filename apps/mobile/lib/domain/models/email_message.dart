/// A sender/recipient address.
class EmailAddress {
  const EmailAddress({required this.name, required this.email});
  final String name;
  final String email;

  String get display => name.isNotEmpty ? name : email;

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
      };

  factory EmailAddress.fromJson(dynamic json) {
    if (json is Map<String, dynamic>) {
      return EmailAddress(
        name: (json['name'] ?? '').toString(),
        email: (json['email'] ?? '').toString(),
      );
    }
    return EmailAddress(name: json?.toString() ?? '', email: json?.toString() ?? '');
  }
}

/// A Gmail message. List responses fill metadata only; [body] is populated when
/// a single message is fetched full.
class EmailMessage {
  const EmailMessage({
    required this.id,
    required this.threadId,
    required this.from,
    required this.subject,
    required this.snippet,
    required this.date,
    required this.unread,
    this.to,
    this.body,
    this.messageIdHeader,
  });

  final String id;
  final String threadId;
  final EmailAddress from;
  final String subject;
  final String snippet;
  final String date;
  final bool unread;
  final String? to;
  final String? body;
  final String? messageIdHeader;

  String get subjectOrNoSubject => subject.trim().isEmpty ? '(no subject)' : subject;

  Map<String, dynamic> toJson() => {
        'id': id,
        'thread_id': threadId,
        'from': from.toJson(),
        'subject': subject,
        'snippet': snippet,
        'date': date,
        'unread': unread,
        'to': to,
        'body': body,
        'message_id_header': messageIdHeader,
      };

  factory EmailMessage.fromJson(Map<String, dynamic> json) => EmailMessage(
        id: (json['id'] ?? '').toString(),
        threadId: (json['thread_id'] ?? '').toString(),
        from: EmailAddress.fromJson(json['from']),
        subject: (json['subject'] ?? '').toString(),
        snippet: (json['snippet'] ?? '').toString(),
        date: (json['date'] ?? '').toString(),
        unread: json['unread'] == true,
        to: json['to'] as String?,
        body: json['body'] as String?,
        messageIdHeader: json['message_id_header'] as String?,
      );
}
