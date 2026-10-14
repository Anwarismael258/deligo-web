enum MozambiqueWalletMethod { mpesa, emola, mkesh }

class MozambiqueWalletValidation {
  MozambiqueWalletValidation._();

  static String normalizeMsisdn(String value) {
    var digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('258') && digits.length >= 12) {
      digits = digits.substring(3);
    }
    // Accept the local format commonly stored by profiles (082..., 084...)
    // as well as the national format without the leading zero (82...).
    if (digits.length == 10 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return digits;
  }

  // Mozambique mobile prefixes used by the three supported wallets:
  // mCel/Tmcel 82/83, Vodacom 84/85 and Movitel 86/87.
  static bool isValidMsisdn(String value) =>
      RegExp(r'^8[2-7][0-9]{7}$').hasMatch(normalizeMsisdn(value));

  static MozambiqueWalletMethod? inferMethod(String value) {
    final msisdn = normalizeMsisdn(value);
    if (msisdn.startsWith('82') || msisdn.startsWith('83')) {
      return MozambiqueWalletMethod.mkesh;
    }
    if (msisdn.startsWith('84') || msisdn.startsWith('85')) {
      return MozambiqueWalletMethod.mpesa;
    }
    if (msisdn.startsWith('86') || msisdn.startsWith('87')) {
      return MozambiqueWalletMethod.emola;
    }
    return null;
  }

  static bool methodMatches(String value, String method) {
    final inferred = inferMethod(value);
    final normalized = method.toLowerCase().replaceAll('-', '');
    return (inferred == MozambiqueWalletMethod.mpesa &&
            normalized == 'mpesa') ||
        (inferred == MozambiqueWalletMethod.emola && normalized == 'emola') ||
        (inferred == MozambiqueWalletMethod.mkesh && normalized == 'mkesh');
  }
}
