part of 'index.dart';

class TetaRealtime {
  TetaRealtime(
    this.token,
    this.prjId,
  );
  final String token;
  final int prjId;

  socket_io.Socket? _socket;
  List<RealtimeSubscription> streams = [];

  Future<void> _openSocket() {
    final completer = Completer<void>();

    if (_socket?.connected == true) {
      completer.complete();
      return completer.future;
    }

    final opts = socket_io.OptionBuilder()
        .setPath('/nosql')
        .setTransports(['websocket'])
        .disableAutoConnect()
        .build();

    _socket = socket_io.io(Constants.tetaUrl, opts);

    _socket?.onConnect((final dynamic _) {
      completer.complete();
    });

    _socket?.on('change', (final dynamic data) {
      final event = SocketChangeEvent.fromJson(data as Map<String, dynamic>);

      for (final stream in streams) {
        if (stream.uid == event.uid) stream.callback(event);
      }
    });

    _socket!.connect();

    return completer.future;
  }

  void _closeStream(final String uid) {
    final stream = streams.firstWhere((final stream) => stream.uid == uid);
    streams.remove(stream);

    if (streams.isEmpty) {
      _socket!.close();
      _socket = null;
    }
  }

  /// Creates a websocket connection to the NoSql database
  /// that listens for events of type [action] and
  /// fires [callback] when the event is emitted.
  ///
  /// Returns a `NoSqlStream`
  ///
  Future<RealtimeSubscription> on({
    final StreamAction action = StreamAction.all,
    final String? collectionId,
    final String? documentId,
    final Function(SocketChangeEvent)? callback,
  }) async {
    if (_socket == null) await _openSocket();

    if (collectionId == null) throw Exception('collectionId is required');
    final docId = action.targetDocument ? documentId : '*';
    if (docId == null) throw Exception('documentId is required');

    final uri = Uri.parse(
      '${Constants.tetaUrl}/stream/listen/${_socket!.id}/${action.type}/$prjId/$collectionId/$docId',
    );

    final res = await http.post(
      uri,
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $token',
      },
    );

    if (res.statusCode != 200) {
      throw Exception('Request resulted in ${res.statusCode} - ${res.body}');
    }

    final uid =
        (json.decode(res.body) as Map<String, dynamic>)['uid'] as String;

    final stream =
        RealtimeSubscription(uid, callback!, () => _closeStream(uid));
    streams.add(stream);
    return stream;
  }

  /// Creates a websocket connection to the NoSql database
  /// that listens for events of type [action] and
  /// fires [callback] when the event is emitted.
  ///
  /// Returns a `NoSqlStream`
  ///
  Stream<SocketChangeEvent> stream({
    final StreamAction action = StreamAction.all,
    final String? collectionId,
    final String? documentId,
  }) async* {
    final streamController = StreamController<SocketChangeEvent>();
    await on(
      collectionId: collectionId,
      callback: (final e) async* {
        streamController.add(e);
      },
    );
    yield* streamController.stream;
  }

  /// Stream all collections without docs
  Stream<List<CollectionObject>> streamCollections({
    final StreamAction action = StreamAction.all,
  }) async* {
    final streamController = StreamController<List<CollectionObject>>();
    on(
      callback: (final e) async {
        final resp = await TetaCMS.instance.client.getCollections();
        streamController.add(resp);
      },
    );
    yield* streamController.stream;
  }

  /// Stream a single collection with its docs only
  Stream<List<dynamic>> streamCollection({
    required final String collectionId,
    final StreamAction action = StreamAction.all,
  }) async* {
    final streamController = StreamController<List<dynamic>>();
    await on(
      collectionId: collectionId,
      callback: (final e) async* {
        final resp = await TetaCMS.instance.client.getCollection(collectionId);
        streamController.add(resp);
      },
    );
    yield* streamController.stream;
  }
}
