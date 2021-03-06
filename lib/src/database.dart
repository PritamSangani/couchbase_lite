part of couchbase_lite;

enum ConcurrencyControl { lastWriteWins, failOnConflict }

class Database {
  Database._internal(this.name);

  static const MethodChannel _methodChannel =
      MethodChannel('com.saltechsystems.couchbase_lite/database');

  static const EventChannel _eventChannel =
      EventChannel('com.saltechsystems.couchbase_lite/databaseEventChannel');
  static final Stream _stream = _eventChannel.receiveBroadcastStream();

  /// Initializes a Couchbase Lite database with the given [dbName].
  static Future<Database> initWithName(String dbName) async {
    await _methodChannel.invokeMethod(
        'initDatabaseWithName', <String, dynamic>{'database': dbName});
    return Database._internal(dbName);
  }

  final String name;

  Map<ListenerToken, StreamSubscription> tokens = {};

  /// The number of documents in the database
  Future<int> get count => _methodChannel
      .invokeMethod('getDocumentCount', <String, dynamic>{'database': name});

  /// Deletes a database of the given [dbName].
  static Future<void> deleteWithName(String dbName) =>
      _methodChannel.invokeMethod(
          'deleteDatabaseWithName', <String, dynamic>{'database': dbName});

  /// Gets a Document object [withId]
  Future<Document> document(String withId) async {
    var _docResult = await _methodChannel.invokeMethod(
        'getDocumentWithId', <String, dynamic>{'database': name, 'id': withId});

    if (_docResult['doc'] == null) {
      return null;
    } else {
      return Document._init(
          _docResult['doc'], _docResult['id'], name, _docResult['sequence']);
    }
  }

  /// Gets a Document object with the given [id]
  @Deprecated('Replaced by `document`.')
  Future<Document> documentWithId(String id) => document(id);

  /// All index names.
  Future<List<String>> get indexes async {
    var result = await _methodChannel
        .invokeMethod('getIndexes', <String, dynamic>{'database': name});

    return List.castFrom<dynamic, String>(result);
  }

  /// Saves [doc] to the database with the document id set by the database. When write operations are executed concurrently, the last write wins by default.
  @Deprecated('Replaced by `saveDocument`.')
  Future<bool> save(MutableDocument doc,
          {ConcurrencyControl concurrencyControl =
              ConcurrencyControl.lastWriteWins}) =>
      saveDocument(doc, concurrencyControl: concurrencyControl);

  /// Saves [doc] to the database with the document id set by the database. When write operations are executed concurrently, the last write wins by default.
  Future<bool> saveDocument(MutableDocument doc,
      {ConcurrencyControl concurrencyControl =
          ConcurrencyControl.lastWriteWins}) async {
    Map<dynamic, dynamic> result;
    if (doc.id == null) {
      result =
          await _methodChannel.invokeMethod('saveDocument', <String, dynamic>{
        'database': name,
        'map': doc.toMap(),
        'concurrencyControl':
            concurrencyControl == ConcurrencyControl.failOnConflict
                ? 'failOnConflict'
                : 'lastWriteWins'
      });
    } else if (doc.sequence != null) {
      result = await _methodChannel
          .invokeMethod('saveDocumentWithId', <String, dynamic>{
        'database': name,
        'id': doc.id,
        'sequence': doc.sequence,
        'map': doc.toMap(),
        'concurrencyControl':
            concurrencyControl == ConcurrencyControl.failOnConflict
                ? 'failOnConflict'
                : 'lastWriteWins'
      });
    } else {
      result = await _methodChannel
          .invokeMethod('saveDocumentWithId', <String, dynamic>{
        'database': name,
        'id': doc.id,
        'map': doc.toMap(),
        'concurrencyControl':
            concurrencyControl == ConcurrencyControl.failOnConflict
                ? 'failOnConflict'
                : 'lastWriteWins'
      });
    }

    if (result['success'] == true) {
      doc._dbname = name;
      doc._id = result['id'];
      doc._sequence = result['sequence'];
      doc._data = Map<String, dynamic>.from(result['doc']);
      return true;
    } else {
      return false;
    }
  }

  /// Deletes document [withId] from the database.
  Future<bool> deleteDocument(String withId) async {
    await _methodChannel.invokeMethod('deleteDocumentWithId',
        <String, dynamic>{'database': name, 'id': withId});

    return true;
  }

  /// Clears all Blobs from the database used to fetch the Blob content.
  Future<bool> clearBlobCache() async {
    await _methodChannel.invokeMethod('clearBlobCache');

    return true;
  }

  /// Creates an index [withName] which could be a value index or a full-text search index.
  /// The name can be used for deleting the index. Creating a new different index with an existing index
  /// name will replace the old index; creating the same index with the same name will be no-ops.
  Future<bool> createIndex(ValueIndex index, {@required String withName}) {
    return _methodChannel.invokeMethod('createIndex', <String, dynamic>{
      'database': name,
      'index': index.toJson(),
      'withName': withName
    });
  }

  /// Deletes index [forName] from the database.
  Future<bool> deleteIndex({@required String forName}) async {
    await _methodChannel.invokeMethod('deleteIndex', <String, dynamic>{
      'database': name,
      'forName': forName,
    });

    return true;
  }

  /// Adds a database change listener on which changes will be posted
  ///
  /// Returns the listener token object for removing the listener.
  ListenerToken addChangeListener(Function(DatabaseChange) callback) {
    var token = ListenerToken();

    tokens[token] = _stream
        .where((data) =>
            (data['database'] == name && data['type'] == 'DatabaseChange'))
        .listen((data) => callback(DatabaseChange(
            this,
            (data['documentIDs'] as List<dynamic>)
                .map((id) => id as String)
                .toList())));

    // Caveat:  Do not call addChangeListener more than once.
    if (tokens.length == 1) {
      _methodChannel.invokeMethod(
          'addChangeListener', <String, dynamic>{'database': name});
    }

    return token;
  }

  /// Adds a document change listener.
  ///
  /// Returns the listener token object for removing the listener.
  ListenerToken addDocumentChangeListener(
      String withId, Function(DocumentChange) callback) {
    var token = ListenerToken();

    tokens[token] = _stream
        .where((data) =>
            (data['database'] == name && data['type'] == 'DatabaseChange') &&
            (data['documentIDs'] as List<Object>).contains(withId))
        .listen((data) {
      callback(DocumentChange(this, withId));
    });

    // Caveat:  Do not call addChangeListener more than once.
    if (tokens.length == 1) {
      _methodChannel.invokeMethod(
          'addChangeListener', <String, dynamic>{'database': name});
    }

    return token;
  }

  /// Removes a change listener with the given listener token.
  Future<ListenerToken> removeChangeListener(ListenerToken token) async {
    var subscription = tokens.remove(token);

    if (subscription != null) {
      await subscription.cancel();
    }

    if (tokens.isEmpty) {
      await _methodChannel.invokeMethod(
          'removeChangeListener', <String, dynamic>{'database': name});
    }

    return token;
  }

  /// Closes database.
  Future<void> close() async {
    for (var token in List.from(tokens.keys)) {
      await removeChangeListener(token);
    }

    await _methodChannel.invokeMethod(
        'closeDatabaseWithName', <String, dynamic>{'database': name});
  }

  //Not including this way of deleting for now because I remove the reference when we close the database
  Future<void> delete() => _methodChannel.invokeMethod(
      'deleteDatabaseWithName', <String, dynamic>{'database': name});

  //Not including this way of disposing for now because I remove the reference when we close the database
  //Future<void> dispose() => _methodChannel.invokeMethod('dispose', <String, dynamic>{'database': name});

  Future<void> compact() => _methodChannel.invokeMethod(
      'compactDatabaseWithName', <String, dynamic>{'database': name});
}

class DocumentChange {
  DocumentChange(this.database, this.documentID);

  /// The database
  final Database database;

  /// The ID of the document that changed
  final String documentID;
}

class DatabaseChange {
  DatabaseChange(this.database, this.documentIDs);

  /// The database
  final Database database;

  /// The IDs of the documents that changed.
  final List<String> documentIDs;
}
