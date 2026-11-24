import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moviebox_glassy/api/models.dart';

// Fixtures are trimmed real responses captured live from
// https://h5-api.aoneroom.com/wefeed-h5api-bff/... on 2026-11-24
// (search "avengers", home, detail for Steps + Rings of Power).

const String _h5HomeJson = r'''{"code": 0, "data": {"operatingList": [{"type": "BANNER", "position": 1, "title": "Banner_Africa", "subjects": [], "banner": {"items": [{"subjectId": "2845168888013275776", "subjectType": 2, "subject": {"subjectId": "2845168888013275776", "subjectType": 2, "title": "Percy Jackson and the Olympians", "description": "", "releaseDate": "2023-12-19", "duration": 0, "genre": "Action,Adventure,Family", "cover": {"url": "https://pbcdn.aoneroom.com/image/2026/11/18/b69cf287e62a381347a901a2d52b6e96.jpg", "width": 1600, "height": 2000, "size": 619370, "format": "jpg", "thumbnail": "", "blurHash": "eUHK^8^$^*?axa}kNIazkCM|?bNKNeofRl%1j[o#t7ofj[NHRjWBjF", "gif": null, "avgHueLight": "#84735a", "avgHueDark": "#665b4a", "id": "0"}, "countryName": "United States", "imdbRatingValue": "7.0", "detailPath": "percy-jackson-and-the-olympians-OxG19N1Uao3", "season": 0}}, {"subjectId": "9168495427082149592", "subjectType": 1, "subject": {"subjectId": "9168495427082149592", "subjectType": 1, "title": "Steps", "description": "", "releaseDate": "2026-11-20", "duration": 6120, "genre": "Animation,Adventure,Comedy", "cover": {"url": "https://pbcdn.aoneroom.com/image/2026/11/23/85bc4482b5a3caea3f0bf103cca323cc.jpg", "width": 1500, "height": 2222, "size": 1925320, "format": "jpg", "thumbnail": "", "blurHash": "eRBp-UkFM{t7MdRzfiNGWAa#DgjXnhR-x]M}adxaogoyt6V[o~t6RQ", "gif": null, "avgHueLight": "#51537d", "avgHueDark": "#464766", "id": "0"}, "countryName": "United States", "imdbRatingValue": "6.8", "detailPath": "steps-qJ0VewZNhVa", "season": 0}}, {"subjectId": "568566274385663264", "subjectType": 1, "subject": {"subjectId": "568566274385663264", "subjectType": 1, "title": "The Beast", "description": "", "releaseDate": "2026-10-09", "duration": 5940, "genre": "Action,Drama,Thriller", "cover": {"url": "https://pbcdn.aoneroom.com/image/2026/10/09/3bfdb5be67786ef949ecc1745c47c4c2.jpg", "width": 1200, "height": 1778, "size": 291348, "format": "jpg", "thumbnail": "", "blurHash": "eFAlzurs#,#,wvnixEs:xZj[1MXRI;NvS2E%EhX7J8j[nOf7t6kCW;", "gif": null, "avgHueLight": "#453627", "avgHueDark": "#45372a", "id": "0"}, "countryName": "United Kingdom", "imdbRatingValue": "5.3", "detailPath": "the-beast-C7GYk6s20G", "season": 0}}]}}, {"type": "SUBJECTS_MOVIE", "position": 3, "title": "Popular Series", "subjects": [{"subjectId": "5074096615720375064", "subjectType": 2, "title": "The Lord of the Rings: The Rings of Power", "description": "", "releaseDate": "2022-09-01", "duration": 0, "genre": "Action,Adventure,Drama", "cover": {"url": "https://pbcdn.aoneroom.com/image/2026/09/29/5aad7dd8d87f5e0ec17986e0d1d13d74.jpg", "width": 1080, "height": 1920, "size": 268506, "format": "jpg", "thumbnail": "", "blurHash": "eeGi1B$i,qsTsm}BS2WWWWWWo1WWNbsnoKn%snWqWWj[e:oKsnWWa|", "gif": null, "avgHueLight": "#783417", "avgHueDark": "#662a11", "id": "0"}, "countryName": "United States", "imdbRatingValue": "6.8", "detailPath": "the-lord-of-the-rings-the-rings-of-power-oWxADnOpP26", "season": 0}, {"subjectId": "2845168888013275776", "subjectType": 2, "title": "Percy Jackson and the Olympians", "description": "", "releaseDate": "2023-12-19", "duration": 0, "genre": "Action,Adventure,Family", "cover": {"url": "https://pbcdn.aoneroom.com/image/2026/11/18/b69cf287e62a381347a901a2d52b6e96.jpg", "width": 1600, "height": 2000, "size": 619370, "format": "jpg", "thumbnail": "", "blurHash": "eUHK^8^$^*?axa}kNIazkCM|?bNKNeofRl%1j[o#t7ofj[NHRjWBjF", "gif": null, "avgHueLight": "#84735a", "avgHueDark": "#665b4a", "id": "0"}, "countryName": "United States", "imdbRatingValue": "7.0", "detailPath": "percy-jackson-and-the-olympians-OxG19N1Uao3", "season": 0}, {"subjectId": "475402426686788376", "subjectType": 2, "title": "Yellowjackets", "description": "", "releaseDate": "2021-11-14", "duration": 0, "genre": "Drama,Horror,Mystery", "cover": {"url": "https://pbcdn.aoneroom.com/image/2026/11/17/16af4dadad5ee3c9e214eaa5c877de56.jpg", "width": 2000, "height": 3000, "size": 1460437, "format": "jpg", "thumbnail": "", "blurHash": "eLGQqM^hIr-TkB=_xsxYoLWC0%oJ$}I;R+EkxYoJs,t6S#t6s.s.WB", "gif": null, "avgHueLight": "#7f5341", "avgHueDark": "#664539", "id": "0"}, "countryName": "United States", "imdbRatingValue": "7.7", "detailPath": "yellowjackets-UWnPLjAl7z", "season": 0}], "banner": null}, {"type": "SPORT_LIVE", "position": 2, "title": "Football Live", "subjects": [], "banner": null}, {"type": "SUBJECTS_MOVIE", "position": 4, "title": "Popular Movie", "subjects": [{"subjectId": "9168495427082149592", "subjectType": 1, "title": "Steps", "description": "", "releaseDate": "2026-11-20", "duration": 6120, "genre": "Animation,Adventure,Comedy", "cover": {"url": "https://pbcdn.aoneroom.com/image/2026/11/23/85bc4482b5a3caea3f0bf103cca323cc.jpg", "width": 1500, "height": 2222, "size": 1925320, "format": "jpg", "thumbnail": "", "blurHash": "eRBp-UkFM{t7MdRzfiNGWAa#DgjXnhR-x]M}adxaogoyt6V[o~t6RQ", "gif": null, "avgHueLight": "#51537d", "avgHueDark": "#464766", "id": "0"}, "countryName": "United States", "imdbRatingValue": "6.8", "detailPath": "steps-qJ0VewZNhVa", "season": 0}, {"subjectId": "1885450268641216864", "subjectType": 1, "title": "Clashing Through the Snow", "description": "", "releaseDate": "2026-11-23", "duration": 6420, "genre": "Comedy,Romance", "cover": {"url": "https://pbcdn.aoneroom.com/image/2026/11/19/fb40a0b5a5250cc13b37ce4e691ce738.jpg", "width": 1080, "height": 1350, "size": 192621, "format": "jpg", "thumbnail": "", "blurHash": "e7BoBjxtukVuRj[Vj?JBn+S}MdRkXmxZt7%2WVWUt6RQ9uR+%0xst7", "gif": null, "avgHueLight": "#5d2927", "avgHueDark": "#5d2c2b", "id": "0"}, "countryName": "United States", "imdbRatingValue": "6.3", "detailPath": "clashing-through-the-snow-AQVuXiHnhf2", "season": 0}], "banner": null}]}}''';
const String _h5SearchJson = r'''{"code": 0, "data": {"pager": {"totalCount": 154}, "items": [{"subjectId": "5608459269503862552", "subjectType": 1, "title": "AVENGERS", "description": "", "releaseDate": "2025-08-24", "duration": 0, "genre": "yoruba", "cover": {"url": "https://pbcdnw.aoneroom.com/image/2026/03/30/4d2dec2acb2cbea6272e58c5ecb3b75d.jpg", "width": 1280, "height": 720, "size": 213070, "format": "jpg", "thumbnail": "", "blurHash": "eNE-p?niI;JBS$}t$ig2NaSNa0-ANxNtWCnmjZR*NbWVItR*j=bZWC", "gif": null, "avgHueLight": "#714d41", "avgHueDark": "#66493f", "id": "0"}, "countryName": "Nigeria", "imdbRatingValue": "0", "detailPath": "avengers-QExqQyMNiG6", "season": 0}, {"subjectId": "6071361600823381168", "subjectType": 1, "title": "Avengers Endgame: Encore", "description": "", "releaseDate": "2026-11-13", "duration": 0, "genre": "Action,Adventure,Sci-Fi", "cover": {"url": "https://pbcdnw.aoneroom.com/image/2026/11/15/48ff13626753ac0a4d8e0c6f23bfcd9d.jpeg", "width": 607, "height": 911, "size": 149492, "format": "jpg", "thumbnail": "", "blurHash": "e4Ad1Nxv4nM{xt~pkCM{RjayM_Rjt8j[Rj-:WBxaj[j]4nWBt7t7t7", "gif": null, "avgHueLight": "#54504b", "avgHueDark": "#54514f", "id": "0"}, "countryName": "United States", "imdbRatingValue": "6.0", "detailPath": "avengers-endgame-encore-Y8fDUGPTue7", "season": 0}, {"subjectId": "8454918444612471512", "subjectType": 2, "title": "Avengers Assemble S1-S5", "description": "", "releaseDate": "2013-05-26", "duration": 0, "genre": "Animation,Action,Adventure", "cover": {"url": "https://pbcdnw.aoneroom.com/image/2026/01/27/a2d6ae396e5719aca648bc7b8a55c5bb.jpg", "width": 1526, "height": 2048, "size": 471853, "format": "jpg", "thumbnail": "", "blurHash": "eBBpFO%20e=|^P?wt69Fo1xa0#s:#kV@X7rXRjxaoIW;v}kBo~$*t7", "gif": null, "avgHueLight": "#514848", "avgHueDark": "#514b4b", "id": "0"}, "countryName": "United States", "imdbRatingValue": "7.0", "detailPath": "avengers-assemble-WH7r7AcCz4a", "season": 0}]}}''';
const String _h5DetailMovieJson = r'''{"code": 0, "data": {"subject": {"subjectId": "9168495427082149592", "subjectType": 1, "title": "Steps", "description": "Blamed for magical mischief at the Royal Ball, stepsister Lilith turns her sister into a frog. She must work with Cinderella and a troll to save the kingdom and prove villains deserve happy endings too.", "releaseDate": "2026-11-20", "duration": 6120, "genre": "Animation,Adventure,Comedy", "cover": {"url": "https://pbcdnw.aoneroom.com/image/2026/11/23/85bc4482b5a3caea3f0bf103cca323cc.jpg", "width": 1500, "height": 2222, "size": 1925320, "format": "jpg", "thumbnail": "", "blurHash": "eRBp-UkFM{t7MdRzfiNGWAa#DgjXnhR-x]M}adxaogoyt6V[o~t6RQ", "gif": null, "avgHueLight": "#51537d", "avgHueDark": "#464766", "id": "0"}, "countryName": "United States", "imdbRatingValue": "6.8", "detailPath": "steps-qJ0VewZNhVa", "season": 0, "dubs": [{"subjectId": "9168495427082149592", "lanName": "Original Audio", "lanCode": "en", "original": true, "type": 0, "detailPath": "steps-qJ0VewZNhVa"}, {"subjectId": "375765028185819848", "lanName": "Arabic dub", "lanCode": "ar", "original": false, "type": 0, "detailPath": "steps-ssTXG2u0Lr"}]}, "resource": {"seasons": [{"se": 0, "maxEp": 0, "allEp": "", "resolutions": [{"resolution": 360, "epNum": 1}, {"resolution": 480, "epNum": 1}, {"resolution": 1080, "epNum": 1}]}]}}}''';
const String _h5DetailSeriesJson = r'''{"code": 0, "data": {"subject": {"subjectId": "5074096615720375064", "subjectType": 2, "title": "The Lord of the Rings: The Rings of Power S1-S3", "description": "Epic drama set thousands of years before the events of J.R.R. Tolkien's 'The Hobbit' and 'The Lord of the Rings' follows an ensemble cast of characters, both familiar and new, as they confront the long-feared re-emergence of evil to Middle-earth.", "releaseDate": "2022-09-01", "duration": 0, "genre": "Action,Adventure,Drama", "cover": {"url": "https://pbcdnw.aoneroom.com/image/2026/09/29/5aad7dd8d87f5e0ec17986e0d1d13d74.jpg", "width": 1080, "height": 1920, "size": 268506, "format": "jpg", "thumbnail": "", "blurHash": "eeGi1B$i,qsTsm}BS2WWWWWWo1WWNbsnoKn%snWqWWj[e:oKsnWWa|", "gif": null, "avgHueLight": "#783417", "avgHueDark": "#662a11", "id": "0"}, "countryName": "United States", "imdbRatingValue": "6.8", "detailPath": "the-lord-of-the-rings-the-rings-of-power-oWxADnOpP26", "season": 0, "dubs": [{"subjectId": "5074096615720375064", "lanName": "Original Audio", "lanCode": "en", "original": true, "type": 0, "detailPath": "the-lord-of-the-rings-the-rings-of-power-oWxADnOpP26"}, {"subjectId": "5773237285395350208", "lanName": "Arabic dub", "lanCode": "ar", "original": false, "type": 0, "detailPath": "the-lord-of-the-rings-the-rings-of-power-Iy6e3WfutS6"}]}, "resource": {"seasons": [{"se": 1, "maxEp": 8, "allEp": "", "resolutions": [{"resolution": 360, "epNum": 8}, {"resolution": 480, "epNum": 8}, {"resolution": 1080, "epNum": 8}, {"resolution": 2160, "epNum": 4}]}, {"se": 2, "maxEp": 8, "allEp": "", "resolutions": [{"resolution": 360, "epNum": 8}, {"resolution": 480, "epNum": 8}, {"resolution": 1080, "epNum": 8}, {"resolution": 2160, "epNum": 1}]}, {"se": 3, "maxEp": 6, "allEp": "", "resolutions": [{"resolution": 360, "epNum": 6}, {"resolution": 480, "epNum": 6}, {"resolution": 1080, "epNum": 6}, {"resolution": 2160, "epNum": 6}]}]}}}''';

void main() {
  group('H5 home', () {
    test('banner items become hero, sections become the flat list', () {
      final feed = parseH5HomeFeed(
        jsonDecode(_h5HomeJson) as Map<String, dynamic>,
      );
      expect(feed.hero.length, 3);
      expect(feed.hero.first.title, isNotEmpty);
      // 3 banner + 3 series + 2 movie subjects, minus 2 that appear
      // in both the banner and a section (Steps is one of them).
      expect(feed.all.length, 6);
      // SPORT_LIVE contributes nothing; ids are unique.
      expect(feed.all.map((s) => s.id).toSet().length, feed.all.length);
      // H5 subjects carry their web detail slug.
      expect(feed.all.first.detailPath, isNotNull);
      expect(feed.all.first.detailPath, contains('-'));
    });
  });

  group('H5 search', () {
    test('data.items parses with detailPath', () {
      final results = parseSearchResults(
        jsonDecode(_h5SearchJson) as Map<String, dynamic>,
      );
      expect(results.length, 3);
      expect(results.first.title, 'AVENGERS');
      expect(results.first.detailPath, isNotNull);
      expect(results.first.posterUrl, startsWith('https://'));
    });
  });

  group('H5 details', () {
    test('movie: no seasons, dubs parsed, not a series', () {
      final d = Details.fromH5Json(
        jsonDecode(_h5DetailMovieJson) as Map<String, dynamic>,
      );
      expect(d.subject.title, 'Steps');
      expect(d.subject.isSeries, isFalse);
      expect(d.isSeries, isFalse);
      expect(d.seasons, isEmpty);
      expect(d.dubs.length, 2);
      expect(d.dubs.first.language, isNotEmpty);
    });

    test('series: 3 seasons with episode counts', () {
      final d = Details.fromH5Json(
        jsonDecode(_h5DetailSeriesJson) as Map<String, dynamic>,
      );
      expect(d.isSeries, isTrue);
      expect(d.seasons.length, 3);
      expect(d.seasons[0].season, 1);
      expect(d.seasons[0].episodes.length, 8);
      expect(d.seasons[2].episodes.length, 6);
      expect(d.dubs.isNotEmpty, isTrue);
    });
  });

  group('Subject detailPath', () {
    test('round-trips through toJson/fromStored', () {
      const s = Subject(
        id: '1',
        title: 'Steps',
        type: MediaType.movie,
        detailPath: 'steps-qJ0VewZNhVa',
      );
      final restored = Subject.fromStored(s.toJson());
      expect(restored.detailPath, 'steps-qJ0VewZNhVa');
      expect(Subject.fromJson({'subjectId': 5, 'title': 'X'}).detailPath,
          isNull);
    });
  });
}
