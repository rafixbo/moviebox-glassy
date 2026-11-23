import 'package:flutter_test/flutter_test.dart';
import 'package:moviebox_glassy/api/models.dart';

/// Parsing tests using real-shaped payloads (fields as returned live by
/// the MovieBox API — verified 2026-11-23).
void main() {
  test('search results parse subjects from data.results[0].subjects', () {
    final subjects = parseSearchResults({
      'code': 0,
      'data': {
        'results': [
          {
            'topicType': 'SUBJECT',
            'subjects': [
              {
                'subjectId': '1319930206253107928',
                'subjectType': 1,
                'title': 'Avengers: Doomsday',
                'releaseDate': '2026-12-18',
                'duration': '2h 45m',
                'genre': 'Action',
                'cover': {'url': 'https://pbcdn.aoneroom.com/image/x.jpg'},
                'imdbRatingValue': '6.5',
                'hasResource': true,
              },
              {
                'subjectId': 42,
                'subjectType': 2,
                'title': 'Squid Game',
                'releaseDate': '2021-09-17',
                'genre': ['Drama', 'Thriller'],
                'cover': {'url': 'https://pbcdn.aoneroom.com/image/y.jpg'},
              },
            ],
          },
        ],
      },
    });
    expect(subjects.length, 2);
    expect(subjects[0].id, '1319930206253107928');
    expect(subjects[0].title, 'Avengers: Doomsday');
    expect(subjects[0].year, '2026');
    expect(subjects[0].isSeries, false);
    expect(subjects[0].rating, '6.5');
    expect(subjects[0].duration, '2h 45m');
    expect(subjects[1].id, '42'); // numeric ids become strings
    expect(subjects[1].isSeries, true);
    expect(subjects[1].genres, ['Drama', 'Thriller']);
  });

  test('search falls back to data.list', () {
    final subjects = parseSearchResults({
      'data': {
        'list': [
          {'subjectId': '7', 'subjectType': 1, 'title': 'Dune'},
        ],
      },
    });
    expect(subjects.length, 1);
    expect(subjects.first.title, 'Dune');
  });

  test('home feed collects banner heroes + unique subjects in order', () {
    final (hero: hero, all: all) = parseHomeFeed({
      'data': {
        'tabId': 2,
        'items': [
          {
            'type': 'BANNER',
            'banner': {
              'banners': [
                {
                  'subjectId': '1',
                  'subject': {
                    'subjectId': '1',
                    'title': 'Hero One',
                    'subjectType': 1,
                    'cover': {'url': 'https://x/1.jpg'},
                  },
                },
              ],
            },
          },
          {
            'type': 'CUSTOM',
            'customData': {
              'items': [
                {
                  'subject': {
                    'subjectId': '1',
                    'title': 'Hero One',
                    'subjectType': 1,
                  },
                },
                {
                  'subject': {
                    'subjectId': '2',
                    'title': 'Second',
                    'subjectType': 2,
                    'releaseDate': '2024-01-01',
                  },
                },
              ],
            },
          },
          {
            'subjects': [
              {'subjectId': '3', 'title': 'Third', 'subjectType': 1},
            ],
          },
        ],
      },
    });
    expect(hero.map((s) => s.id).toList(), ['1']);
    expect(all.map((s) => s.id).toList(), ['1', '2', '3']);
    expect(all[1].isSeries, true);
  });

  test('details parse seasons from season-info + dubs', () {
    final d = Details.fromJson(
      {
        'data': {
          'subjectId': '9',
          'subjectType': 2,
          'title': 'Test Show',
          'description': 'A show.',
          'genre': 'Drama',
          'cover': {'url': 'https://x/9.jpg'},
          'dubs': [
            {
              'subjectId': '10',
              'lanName': 'Hindi',
              'title': 'Test Show [Hindi]',
            },
          ],
          'resourceDetectors': [
            {
              'downloadUrl': 'https://cdn.example.com/ep1.mp4',
              'resourceId': 'r1',
              'firstSize': '123456',
              'uploadBy': 'uploader',
            },
          ],
        },
      },
      {
        'data': {
          'seasons': [
            {
              'se': 1,
              'episodeNumbers': [1, 2, 3],
            },
            {'se': 2, 'maxEp': 2},
          ],
        },
      },
    );
    expect(d.subject.title, 'Test Show');
    expect(d.isSeries, true);
    expect(d.seasons.length, 2);
    expect(d.seasons[0].episodes, [1, 2, 3]);
    expect(d.seasons[1].episodes, [1, 2]);
    expect(d.dubs.single.language, 'Hindi');
    expect(d.detectors.single['resourceId'], 'r1');
  });

  test('stream sources: placeholder filtered, sorted highest first', () {
    const placeholder =
        'https://macdn.aoneroom.com/other/2026/10/10/80da52722ee7de7a4303290af6783424.mp4';
    final sources = parseStreamSources(
      playInfo: {
        'data': {
          'streams': [
            {'url': 'https://cdn.example.com/480.mp4', 'resolution': 480},
          ],
        },
      },
      resource: {
        'data': {
          'list': [
            {
              'resourceLink': placeholder,
              'resolution': 1080,
              'size': '100',
              'resourceId': 'r1',
            },
            {
              'resourceLink': 'https://cdn.example.com/720.mp4',
              'resolution': 720,
              'size': '200',
              'uploadBy': 'up',
              'resourceId': 'r2',
            },
            {
              'resourceLink': 'https://cdn.example.com/720.mp4?sign=x',
              'resolution': 720,
              'size': '200',
              'resourceId': 'r3',
            },
          ],
        },
      },
      detectors: [
        {'downloadUrl': 'https://cdn.example.com/det.mp4', 'resourceId': 'r4'},
      ],
      season: 0,
      episode: 0,
    );
    // Placeholder dropped, duplicate 720 (same base URL) deduped.
    expect(sources.map((s) => s.url), [
      'https://cdn.example.com/720.mp4',
      'https://cdn.example.com/480.mp4',
      'https://cdn.example.com/det.mp4',
    ]);
    expect(sources.first.label, '720p');
    expect(sources.first.uploader, 'up');
  });

  test('captions skip empty/tiny entries', () {
    final caps = parseCaptions({
      'data': {
        'extCaptions': [
          {'lanName': 'English', 'url': 'https://x/en.srt', 'size': 5000},
          {'lanName': 'Hindi', 'url': '', 'size': 5000},
          {'lanName': 'Tiny', 'url': 'https://x/t.srt', 'size': 10},
          {'lanName': 'English', 'url': 'https://x/en.srt', 'size': 5000},
        ],
      },
    });
    expect(caps.length, 1);
    expect(caps.single.name, 'English');
  });
}
