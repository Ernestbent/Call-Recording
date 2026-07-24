class DraftPaymentCustomer {
  final String customerId;
  final String customerName;
  final String phoneNumber;
  final String? imageUrl;
  final int draftPaymentCount;

  const DraftPaymentCustomer({
    required this.customerId,
    required this.customerName,
    required this.phoneNumber,
    required this.imageUrl,
    required this.draftPaymentCount,
  });
}
