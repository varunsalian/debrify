import 'dart:convert';
import 'package:http/http.dart' as http;

bool catalogParentsRequest(http.Request r) =>
    r.url.host == 'graphql.imdb.com' &&
    (jsonDecode(r.body)['query'] as String).contains('query ParentsGuide');
bool catalogImdbRequest(http.Request r) =>
    r.url.host == 'graphql.imdb.com' &&
    (jsonDecode(r.body)['query'] as String).contains('query Enrich');

http.Response catalogParentsResponse() => http.Response(
  jsonEncode({
    'data': {
      'title': {
        'parentsGuide': {
          'categories': [
            {
              'category': {'id': 'nudity', 'text': 'Sex & Nudity'},
              'severity': {'text': 'Moderate', 'votedFor': 8},
              'totalSeverityVotes': 10,
              'guideItems': {
                'edges': [
                  {
                    'node': {
                      'isSpoiler': false,
                      'text': {'plainText': 'Fixed original parents guide.'},
                    },
                  },
                ],
              },
            },
          ],
        },
      },
    },
  }),
  200,
);

http.Response catalogRichImdbResponse() => http.Response(
  jsonEncode({
    'data': {
      'title': {
        'certificate': {'rating': 'PG-13'},
        'metacritic': {
          'metascore': {'score': 87},
        },
        'ratingsSummary': {'aggregateRating': 8.7, 'voteCount': 123},
        'runtime': {
          'seconds': 6000,
          'displayableProperty': {
            'value': {'plainText': '100 min'},
          },
        },
        'principalCredits': [
          {
            'category': {'text': 'Director'},
            'credits': [
              {
                'name': {
                  'nameText': {'text': 'Rich Director'},
                },
              },
            ],
          },
          {
            'category': {'text': 'Stars'},
            'credits': [
              {
                'name': {
                  'nameText': {'text': 'Rich Actor'},
                },
                'characters': [
                  {'name': 'Original Role'},
                ],
              },
            ],
          },
        ],
        'countriesOfOrigin': {
          'countries': [
            {'text': 'Fixture Country'},
          ],
        },
      },
    },
  }),
  200,
);
