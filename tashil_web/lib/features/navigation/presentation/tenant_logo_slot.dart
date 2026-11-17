import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/m3_color_roles.dart';

/// Circular tenant mark for the sidebar and the narrow rail.
///
/// Uses an uploaded [logoUrl] (or an explicit [logoImage]) when one is
/// present. An empty URL, a missing profile field, or a failed image load
/// falls back to the letter avatar (Adeco → "A").
class TenantLogoSlot extends StatelessWidget {
  final String tenantSlug;
  final String? logoUrl;

  /// Pre-built image (tests, or a future local preview). Wins over [logoUrl].
  final ImageProvider<Object>? logoImage;
  final double radius;

  const TenantLogoSlot({
    super.key,
    required this.tenantSlug,
    this.logoUrl,
    this.logoImage,
    this.radius = 20.0,
  });

  static String letterForSlug(String tenantSlug) {
    final normalized = ApiClient.normalizeDataTenantSlug(tenantSlug);
    if (normalized.isEmpty) return 'A';
    return normalized[0].toUpperCase();
  }

  /// Empty and missing URLs resolve to null so the letter avatar shows.
  /// A null [logoUrl] falls back to the tenant profile's optional `logo_url`.
  /// An explicit empty string does not, so a profile with no logo stays a letter.
  static String? resolveLogoUrl({
    required String tenantSlug,
    String? logoUrl,
  }) {
    final passed = logoUrl?.trim() ?? '';
    if (passed.isNotEmpty) return passed;
    if (logoUrl != null) return null;
    final catalog =
        ApiClient.getTenantProfileBySlug(tenantSlug).logoUrl.trim();
    return catalog.isEmpty ? null : catalog;
  }

  static ImageProvider<Object>? resolveImage({
    required String tenantSlug,
    String? logoUrl,
    ImageProvider<Object>? logoImage,
  }) {
    if (logoImage != null) return logoImage;
    final url = resolveLogoUrl(tenantSlug: tenantSlug, logoUrl: logoUrl);
    if (url == null) return null;
    return NetworkImage(url);
  }

  @override
  Widget build(BuildContext context) {
    final image = resolveImage(
      tenantSlug: tenantSlug,
      logoUrl: logoUrl,
      logoImage: logoImage,
    );
    final mark = image == null
        ? _letter(context)
        : ClipOval(
            child: SizedBox(
              width: radius * 2,
              height: radius * 2,
              child: Image(
                image: image,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => _letter(context),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return _letter(context);
                },
              ),
            ),
          );
    return KeyedSubtree(
      key: const ValueKey('sidebar_tenant_logo'),
      child: mark,
    );
  }

  Widget _letter(BuildContext context) {
    final theme = Theme.of(context);
    final normalized = ApiClient.normalizeDataTenantSlug(tenantSlug);
    return CircleAvatar(
      radius: radius,
      backgroundColor: TenantBrandSeeds.getSeedForTenant(normalized),
      child: Text(
        letterForSlug(tenantSlug),
        style: theme.textTheme.titleMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
