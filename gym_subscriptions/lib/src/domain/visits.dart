// Check-in: a member's visit, and whether the desk may let the member in. Pure Dart.

import 'models.dart';

/// One arrival of a member, recorded at the desk.
class Visit {
  Visit({
    required this.id,
    required this.subscriptionId,
    required this.customerId,
    required this.at,
    this.local = false,
  });

  final String id;
  final String subscriptionId;
  final String customerId;
  final DateTime at;

  /// Kept on this device only (the demo, or a server that has no visits yet).
  /// A local visit of a punch card takes one entry off the number the server sent.
  final bool local;

  Map<String, Object?> toJson() => {
        'id': id,
        'subscriptionId': subscriptionId,
        'customerId': customerId,
        'at': at.toIso8601String(),
        'local': local,
      };

  factory Visit.fromJson(Map<String, dynamic> j) => Visit(
        id: '${j['id']}',
        subscriptionId: '${j['subscriptionId']}',
        customerId: '${j['customerId']}',
        at: DateTime.parse('${j['at']}'),
        local: j['local'] == true,
      );
}

/// ok: recorded at once. warn: recorded, with something the desk should know.
/// blocked: not recorded unless the desk decides to let the member in anyway.
enum EntryLevel { ok, warn, blocked }

/// What the desk can do about a warning or a block.
enum EntryFix { none, renew, collect }

/// The answer to "may this member come in now?".
class EntryCheck {
  const EntryCheck({
    required this.level,
    required this.message,
    this.subscription,
    this.fix = EntryFix.none,
    this.alreadyToday = false,
  });

  final EntryLevel level;

  /// Why (a warning or a block); for [EntryLevel.ok], what is left ("6 entries left").
  final String message;

  /// The membership the visit is recorded on; null when the member has none.
  final Subscription? subscription;
  final EntryFix fix;

  /// A visit of this membership was already recorded today.
  final bool alreadyToday;
}
