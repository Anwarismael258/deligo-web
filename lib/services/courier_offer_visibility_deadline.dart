/// A client-side display guard only. The backend remains authoritative for
/// whether an offer can be viewed or accepted.
class CourierOfferVisibilityDeadline {
  const CourierOfferVisibilityDeadline._();

  static const maxLocalOfferVisibility = Duration(seconds: 25);

  static DateTime? activeCachedDeadline(DateTime? cached, {DateTime? now}) {
    final reference = (now ?? DateTime.now()).toUtc();
    return cached?.toUtc().isAfter(reference) == true ? cached!.toUtc() : null;
  }

  static bool shouldReplaceCachedDeadline({
    DateTime? current,
    required DateTime incoming,
    DateTime? now,
  }) {
    final reference = (now ?? DateTime.now()).toUtc();
    return current == null ||
        !current.toUtc().isAfter(reference) ||
        incoming.toUtc().isBefore(current.toUtc());
  }

  static DateTime? calculate({
    required DateTime receivedAt,
    required DateTime? dispatchExpiresAt,
    required bool hasAttemptId,
    DateTime? serverOfferExpiresAt,
  }) {
    if (!hasAttemptId || dispatchExpiresAt == null) return null;

    final now = receivedAt.toUtc();
    final dispatchExpiry = dispatchExpiresAt.toUtc();
    if (!dispatchExpiry.isAfter(now)) return null;

    var deadline = now.add(maxLocalOfferVisibility);
    if (serverOfferExpiresAt != null &&
        serverOfferExpiresAt.toUtc().isBefore(deadline)) {
      deadline = serverOfferExpiresAt.toUtc();
    }
    if (dispatchExpiry.isBefore(deadline)) deadline = dispatchExpiry;
    return deadline.isAfter(now) ? deadline : null;
  }
}
