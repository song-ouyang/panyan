import 'package:flutter_test/flutter_test.dart';
import 'package:wanpan_diary/features/auth/domain/auth_return_path.dart';

void main() {
  test('safeAuthReturnTo preserves an in-app path and its query', () {
    expect(
      safeAuthReturnTo('/route-submissions/new?gymId=gym-1'),
      '/route-submissions/new?gymId=gym-1',
    );
  });

  test('safeAuthReturnTo rejects external and auth-loop destinations', () {
    expect(safeAuthReturnTo('https://example.com'), '/gyms');
    expect(safeAuthReturnTo('//example.com/profile'), '/gyms');
    expect(safeAuthReturnTo('/login?from=/profile'), '/gyms');
    expect(safeAuthReturnTo('/profile/setup'), '/gyms');
    expect(safeAuthReturnTo('/splash'), '/gyms');
    expect(safeAuthReturnTo('/onboarding'), '/gyms');
  });
}
