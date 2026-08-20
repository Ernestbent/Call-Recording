class DraftPaymentCustomer {
  final String customerId;
  final String customerName;
  final String phoneNumber;
  final String? imageUrl;
  final int draftPaymentCount;
  final List<String> paymentEntryIds;
  final DateTime? latestPaymentEntryCreatedAt;

  const DraftPaymentCustomer({
    required this.customerId,
    required this.customerName,
    required this.phoneNumber,
    required this.imageUrl,
    required this.draftPaymentCount,
    this.paymentEntryIds = const [],
    this.latestPaymentEntryCreatedAt,
  });
}
