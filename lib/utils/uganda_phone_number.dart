class UgandaPhoneNumber {
  static final RegExp _internationalMobile = RegExp(
    r'^(?:\+?256|00256)(7\d{8})$',
  );
  static final RegExp _mobileWithoutTrunkPrefix = RegExp(r'^(7\d{8})$');
  static final RegExp _localMobile = RegExp(r'^07\d{8}$');

  const UgandaPhoneNumber._();

  static String normalize(String rawPhoneNumber) {
    final compact = rawPhoneNumber.trim().replaceAll(RegExp(r'[\s().-]'), '');

    if (_localMobile.hasMatch(compact)) {
      return compact;
    }

    final internationalMatch = _internationalMobile.firstMatch(compact);
    if (internationalMatch != null) {
      return '0${internationalMatch.group(1)}';
    }

    final localWithoutPrefixMatch = _mobileWithoutTrunkPrefix.firstMatch(
      compact,
    );
    if (localWithoutPrefixMatch != null) {
      return '0${localWithoutPrefixMatch.group(1)}';
    }

    return rawPhoneNumber.trim();
  }
}
