import 'package:flutter_test/flutter_test.dart';
import 'package:tashil_web/features/navigation/app_page_route.dart';

void main() {
  group('AppPageRoute', () {
    test('reads the page from a portal path', () {
      expect(AppPageRoute.pageSlugFromPath('/adeco/sell-in'), 'sell-in');
      expect(AppPageRoute.pageSlugFromPath('/portal/adeco/sell-out'),
          'sell-out');
      expect(AppPageRoute.pageSlugFromPath('/ADECO/Sell-In/'), 'sell-in');
    });

    test('no page or unknown page falls back to Dashboard', () {
      expect(AppPageRoute.pageSlugFromPath('/adeco'), '');
      expect(AppPageRoute.pageSlugFromPath('/'), '');
      expect(AppPageRoute.pageSlugFromPath('/adeco/nope'), '');
      expect(AppPageRoute.indexForSlug(''), 0);
      expect(AppPageRoute.indexForSlug('nope'), 0);
    });

    test('index and slug round-trip for every page', () {
      for (var i = 1; i < AppPageRoute.pageSlugs.length; i++) {
        final path =
            AppPageRoute.pathFor('adeco', AppPageRoute.slugForIndex(i));
        expect(AppPageRoute.indexForSlug(AppPageRoute.pageSlugFromPath(path)),
            i);
      }
      expect(AppPageRoute.indexForSlug('sell-in'), 2);
      expect(AppPageRoute.pathFor('adeco', AppPageRoute.slugForIndex(0)),
          '/adeco');
      expect(AppPageRoute.pathFor('adeco', 'sell-in'), '/adeco/sell-in');
    });

    test('unknownPageSlugFromPath is null for Dashboard and known pages', () {
      expect(AppPageRoute.unknownPageSlugFromPath('/adeco'), isNull);
      expect(AppPageRoute.unknownPageSlugFromPath('/adeco/'), isNull);
      expect(AppPageRoute.unknownPageSlugFromPath('/'), isNull);
      expect(AppPageRoute.unknownPageSlugFromPath('/adeco/sell-in'), isNull);
      expect(AppPageRoute.unknownPageSlugFromPath('/portal/adeco/sell-out'),
          isNull);
      expect(AppPageRoute.unknownPageSlugFromPath('/admin'), isNull);
    });

    test('unknownPageSlugFromPath returns the bad segment', () {
      expect(AppPageRoute.unknownPageSlugFromPath('/adeco/nope'), 'nope');
      expect(
        AppPageRoute.unknownPageSlugFromPath('/portal/adeco/this-page-does-not-exist'),
        'this-page-does-not-exist',
      );
      expect(AppPageRoute.unknownPageSlugFromPath('/ADECO/NoPe/'), 'nope');
    });

    test('slugToPreserveFromPath keeps unknown slugs and known pages', () {
      expect(AppPageRoute.slugToPreserveFromPath('/adeco'), '');
      expect(AppPageRoute.slugToPreserveFromPath('/adeco/sell-in'), 'sell-in');
      expect(AppPageRoute.slugToPreserveFromPath('/adeco/nope'), 'nope');
      expect(
        AppPageRoute.slugToPreserveFromPath('/portal/adeco/this-page-does-not-exist'),
        'this-page-does-not-exist',
      );
    });
  });
}
