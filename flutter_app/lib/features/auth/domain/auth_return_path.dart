/// Keeps post-auth navigation inside the app and away from auth-loop routes.
String safeAuthReturnTo(String? value, {String fallback = '/gyms'}) {
  if (value == null || !value.startsWith('/') || value.startsWith('//')) {
    return fallback;
  }

  final uri = Uri.tryParse(value);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return fallback;

  final path = uri.path;
  if (path == '/login' ||
      path.startsWith('/login/') ||
      path == '/profile/setup' ||
      path == '/splash' ||
      path == '/onboarding' ||
      path.startsWith('/onboarding/')) {
    return fallback;
  }
  return uri.toString();
}
