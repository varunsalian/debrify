import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/channel_hub.dart';
import 'package:debrify/services/channel_hub_service.dart';

void main() {
  group('Channel Hub Tests', () {
    test('ChannelHub model serialization', () {
      final series = SeriesInfo(
        id: 1,
        name: 'Breaking Bad',
        imageUrl: 'https://example.com/image.jpg',
        summary: 'A chemistry teacher turned drug dealer',
        genres: ['Drama', 'Crime'],
        status: 'Ended',
        rating: 9.5,
        premiered: '2008-01-20',
        ended: '2013-09-29',
      );

      final hub = ChannelHub(
        id: 'test-id',
        name: 'Test Hub',
        series: [series],
        createdAt: DateTime(2024, 1, 1),
      );

      // Test serialization
      final json = hub.toJson();
      expect(json['id'], 'test-id');
      expect(json['name'], 'Test Hub');
      expect(json['series'], isA<List>());
      expect(json['series'].length, 1);

      // Test deserialization
      final deserializedHub = ChannelHub.fromJson(json);
      expect(deserializedHub.id, hub.id);
      expect(deserializedHub.name, hub.name);
      expect(deserializedHub.series.length, 1);
      expect(deserializedHub.series.first.name, 'Breaking Bad');
    });

    test('SeriesInfo from TVMaze show', () {
      final tvMazeShow = {
        'id': 169,
        'name': 'Breaking Bad',
        'image': {'medium': 'https://example.com/image.jpg'},
        'summary': '<p>Breaking Bad follows protagonist Walter White...</p>',
        'genres': ['Drama', 'Crime', 'Thriller'],
        'status': 'Ended',
        'rating': {'average': 9.2},
        'premiered': '2008-01-20',
        'ended': '2013-09-29',
      };

      final series = SeriesInfo.fromTVMazeShow(tvMazeShow);
      
      expect(series.id, 169);
      expect(series.name, 'Breaking Bad');
      expect(series.imageUrl, 'https://example.com/image.jpg');
      expect(series.summary, 'Breaking Bad follows protagonist Walter White...');
      expect(series.genres, ['Drama', 'Crime', 'Thriller']);
      expect(series.status, 'Ended');
      expect(series.rating, 9.2);
      expect(series.premiered, '2008-01-20');
      expect(series.ended, '2013-09-29');
    });

    test('ChannelHubService ID generation', () {
      final id1 = ChannelHubService.generateId();
      
      expect(id1, isNotEmpty);
      expect(id1, isA<String>());
      
      // Test that ID is numeric (timestamp-based)
      expect(int.tryParse(id1), isNotNull);
    });
  });
} 