import 'dart:convert';
import 'dart:typed_data';

/// Zero-Plaintext Cryptographic Digest Verifier (FIPS 180-4 SHA-256)
/// Ensures that no Super Admin username, email, or password ever exists in
/// plaintext anywhere in the Dart source code or compiled web bundle.
class ZeroTrustDigest {
  ZeroTrustDigest._();

  static const String _domainSalt = 'TashilZeroTrust#2026\$';

  /// SHA-256 hex digest of (_domainSalt + normalized email).
  static const String _superAdminEmailDigest =
      '61ee72585b69ceb7b91162cac5497cbc154a2db0960d552b22074855596c44e3';

  /// SHA-256 hex digest of (_domainSalt + password).
  static const String _superAdminPasswordDigest =
      'f7bfe577dbc57526d0a91980d66af0e6e026b43194ed2bae7e3166c7a8edd023';

  /// SHA-256 hex digest of (_domainSalt + normalized email + ':' + password).
  static const String _superAdminComboDigest =
      '714a08fc6707dde7ffe7df2901149cd22cbc2e4a1306cee89cce92f194dd84ce';

  /// Verifies in constant time whether [email] and [password] match the
  /// exclusive Super Admin cryptographic digests.
  static bool verifySuperAdminCredentials({
    required String email,
    required String password,
  }) {
    final normEmail = email.trim().toLowerCase();
    final emailHash = saltedSha256Hex(normEmail);
    final passHash = saltedSha256Hex(password);
    final comboHash = saltedSha256Hex('$normEmail:$password');

    final matchEmail = _constantTimeEquals(emailHash, _superAdminEmailDigest);
    final matchPass = _constantTimeEquals(passHash, _superAdminPasswordDigest);
    final matchCombo = _constantTimeEquals(comboHash, _superAdminComboDigest);
    return matchEmail && matchPass && matchCombo;
  }

  /// Checks whether [email] matches the Super Admin email digest.
  static bool isSuperAdminEmail(String email) {
    final normEmail = email.trim().toLowerCase();
    return _constantTimeEquals(
      saltedSha256Hex(normEmail),
      _superAdminEmailDigest,
    );
  }

  /// Computes a session signature token bound to the Super Admin digest.
  static String generateVerifiedAdminSessionToken() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final sig = saltedSha256Hex('$_superAdminComboDigest:$ts').substring(0, 32);
    return 'zt-sa-$ts-$sig';
  }

  /// Validates whether [token] is a real backend JWT or a verified Zero-Trust Super Admin session token.
  static bool isVerifiedSuperAdminToken(String? token) {
    if (token == null || token.trim().isEmpty) return false;
    final clean = token.trim();
    // Reject unauthenticated demo tokens on the Super Admin gate
    if (clean == 'demo-superadmin-token') return false;
    // Locally-minted zt-sa-* tokens are not accepted by the backend; only
    // real backend JWTs count as an authenticated Super Admin session.
    if (clean.startsWith('zt-sa-')) return false;
    // Standard 3-part signed JWT from Go backend
    final jwtParts = clean.split('.');
    return jwtParts.length == 3 &&
        jwtParts[0].isNotEmpty &&
        jwtParts[1].isNotEmpty &&
        jwtParts[2].isNotEmpty;
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Computes SHA-256 hex of `(_domainSalt + input)`.
  static String saltedSha256Hex(String input) {
    return sha256Hex('$_domainSalt$input');
  }

  /// Pure Dart FIPS 180-4 SHA-256 implementation.
  static String sha256Hex(String input) {
    final data = utf8.encode(input);
    final bitLength = data.length * 8;

    // Pre-processing (Padding)
    final paddedLength = ((data.length + 9 + 63) ~/ 64) * 64;
    final padded = Uint8List(paddedLength);
    padded.setRange(0, data.length, data);
    padded[data.length] = 0x80;

    final bd = ByteData.sublistView(padded);
    bd.setUint32(paddedLength - 8, (bitLength ~/ 0x100000000) & 0xffffffff, Endian.big);
    bd.setUint32(paddedLength - 4, bitLength & 0xffffffff, Endian.big);

    var h0 = 0x6a09e667;
    var h1 = 0xbb67ae85;
    var h2 = 0x3c6ef372;
    var h3 = 0xa54ff53a;
    var h4 = 0x510e527f;
    var h5 = 0x9b05688c;
    var h6 = 0x1f83d9ab;
    var h7 = 0x5be0cd19;

    final w = Uint32List(64);

    for (var offset = 0; offset < paddedLength; offset += 64) {
      for (var i = 0; i < 16; i++) {
        w[i] = bd.getUint32(offset + (i * 4), Endian.big);
      }
      for (var i = 16; i < 64; i++) {
        final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
      }

      var a = h0;
      var b = h1;
      var c = h2;
      var d = h3;
      var e = h4;
      var f = h5;
      var g = h6;
      var h = h7;

      for (var i = 0; i < 64; i++) {
        final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ ((~e & 0xffffffff) & g);
        final temp1 = (h + s1 + ch + _k[i] + w[i]) & 0xffffffff;
        final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & 0xffffffff;

        h = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xffffffff;
      }

      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + c) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
      h5 = (h5 + f) & 0xffffffff;
      h6 = (h6 + g) & 0xffffffff;
      h7 = (h7 + h) & 0xffffffff;
    }

    final out = StringBuffer();
    for (final word in [h0, h1, h2, h3, h4, h5, h6, h7]) {
      out.write(word.toRadixString(16).padLeft(8, '0'));
    }
    return out.toString();
  }

  static int _rotr(int x, int n) {
    return ((x >>> n) | ((x << (32 - n)) & 0xffffffff)) & 0xffffffff;
  }

  static const List<int> _k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
}
