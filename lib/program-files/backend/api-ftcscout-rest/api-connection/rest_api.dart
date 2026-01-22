import 'dart:convert';
import 'package:http/http.dart' as http;

/// Base exception for all FTCScout API errors.
class FtcScoutApiException implements Exception {
  final String message;
  final Uri? uri;
  final int? statusCode;
  final Object? innerError;

  FtcScoutApiException(
      this.message, {
        this.uri,
        this.statusCode,
        this.innerError,
      });

  @override
  String toString() {
    final buf = StringBuffer('FtcScoutApiException: $message');
    if (statusCode != null) buf.write(' (statusCode=$statusCode)');
    if (uri != null) buf.write(' [uri=$uri]');
    if (innerError != null) buf.write(' [innerError=$innerError]');
    return buf.toString();
  }
}

/// A wrapper for the FTCScout REST API (https://api.ftcscout.org/rest/v1).
class FtcScoutRestApi {
  static const String _host = 'api.ftcscout.org';
  static const String _basePath = '/rest/v1';

  final http.Client _client;

  FtcScoutRestApi({http.Client? client}) : _client = client ?? http.Client();

  /// Builds a URI for a given path and set of query parameters.
  Uri _buildUri(
      String path, {
        Map<String, dynamic>? queryParameters,
      }) {
    if (path.startsWith('/')) {
      path = path.substring(1);
    }

    final qp = <String, String>{};

    if (queryParameters != null) {
      for (final entry in queryParameters.entries) {
        final value = entry.value;
        if (value == null) continue;

        if (value is DateTime) {
          qp[entry.key] = value.toIso8601String();
        } else if (value is List) {
          qp[entry.key] = value.join(',');
        } else {
          qp[entry.key] = value.toString();
        }
      }
    }

    return Uri.https(_host, '$_basePath/$path', qp.isEmpty ? null : qp);
  }

  /// Sends a GET request to the specified path and returns the decoded JSON.
  Future<dynamic> _get(
      String path, {
        Map<String, dynamic>? queryParameters,
      }) async {
    final uri = _buildUri(path, queryParameters: queryParameters);

    http.Response response;
    try {
      response = await _client.get(uri);
    } catch (e) {
      throw FtcScoutApiException(
        'Failed to send request',
        uri: uri,
        innerError: e,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FtcScoutApiException(
        'Request failed with status code ${response.statusCode}',
        uri: uri,
        statusCode: response.statusCode,
      );
    }

    try {
      return json.decode(response.body);
    } catch (e) {
      throw FtcScoutApiException(
        'Failed to decode JSON response',
        uri: uri,
        innerError: e,
      );
    }
  }

  /// Closes the underlying HTTP client.
  void close() {
    _client.close();
  }

  /// Fetches details for a specific team.
  Future<dynamic> getTeam(int teamNumber) {
    return _get('teams/$teamNumber');
  }

  /// Fetches events a team participated in during a specific season.
  Future<dynamic> getTeamEvents({
    required int teamNumber,
    required int season,
  }) {
    return _get('teams/$teamNumber/events/$season');
  }

  /// Fetches awards won by a team.
  Future<dynamic> getTeamAwards({
    required int teamNumber,
    int? season,
    String? eventCode,
  }) {
    return _get(
      'teams/$teamNumber/awards',
      queryParameters: {
        if (season != null) 'season': season,
        if (eventCode != null) 'eventCode': eventCode,
      },
    );
  }

  /// Fetches match history for a team.
  Future<dynamic> getTeamMatches({
    required int teamNumber,
    int? season,
    String? eventCode,
  }) {
    return _get(
      'teams/$teamNumber/matches',
      queryParameters: {
        if (season != null) 'season': season,
        if (eventCode != null) 'eventCode': eventCode,
      },
    );
  }

  /// Fetches quick statistics (like averages) for a team.
  Future<dynamic> getTeamQuickStats({
    required int teamNumber,
    int? season,
    String? region,
  }) {
    return _get(
      'teams/$teamNumber/quick-stats',
      queryParameters: {
        if (season != null) 'season': season,
        if (region != null) 'region': region,
      },
    );
  }

  /// Searches for teams based on criteria.
  Future<dynamic> searchTeams({
    String? region,
    int? limit,
    String? searchText,
  }) {
    return _get(
      'teams/search',
      queryParameters: {
        if (region != null) 'region': region,
        if (limit != null) 'limit': limit,
        if (searchText != null && searchText.isNotEmpty)
          'searchText': searchText,
      },
    );
  }

  /// Fetches details for a specific event.
  Future<dynamic> getEvent({
    required int season,
    required String code,
  }) {
    return _get('events/$season/$code');
  }

  /// Fetches all matches for a specific event.
  Future<dynamic> getEventMatches({
    required int season,
    required String code,
  }) {
    return _get('events/$season/$code/matches');
  }

  /// Fetches awards given out at a specific event.
  Future<dynamic> getEventAwards({
    required int season,
    required String code,
  }) {
    return _get('events/$season/$code/awards');
  }

  /// Fetches all teams participating in a specific event.
  Future<dynamic> getEventTeams({
    required int season,
    required String code,
  }) {
    return _get('events/$season/$code/teams');
  }

  /// Searches for events based on criteria.
  Future<dynamic> searchEvents({
    String? region,
    String? type,
    bool? hasMatches,
    DateTime? start,
    DateTime? end,
    int? limit,
    String? searchText,
  }) {
    return _get(
      'events/search',
      queryParameters: {
        if (region != null) 'region': region,
        if (type != null) 'type': type,
        if (hasMatches != null) 'hasMatches': hasMatches,
        if (start != null) 'start': start,
        if (end != null) 'end': end,
        if (limit != null) 'limit': limit,
        if (searchText != null && searchText.isNotEmpty)
          'searchText': searchText,
      },
    );
  }
}
