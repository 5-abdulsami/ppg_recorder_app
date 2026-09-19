import 'dart:async';

/// Serialises asynchronous operations so they never interleave.
///
/// Used to keep camera start/stop/dispose calls strictly ordered even when
/// lifecycle events and user actions arrive concurrently.
class AsyncMutex {
  Future<void> _last = Future<void>.value();

  /// Runs [action] after every previously scheduled action has completed.
  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<void>();
    final previous = _last;
    _last = completer.future;
    return previous.then((_) => action()).whenComplete(completer.complete);
  }
}
