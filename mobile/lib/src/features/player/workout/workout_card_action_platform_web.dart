import 'dart:async';
import 'dart:typed_data';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'workout_card_action_adapter.dart';
import 'workout_card_web_action_adapter.dart';

WorkoutCardActionAdapter createWorkoutCardActionAdapter(Uint8List pngBytes) =>
    WebWorkoutCardActionAdapter(_BrowserWorkoutCardBindings(pngBytes));

class _BrowserWorkoutCardBindings implements WorkoutCardWebBindings {
  _BrowserWorkoutCardBindings(Uint8List pngBytes) {
    _blob = web.Blob(<web.BlobPart>[pngBytes.toJS].toJS,
        web.BlobPropertyBag(type: 'image/png'));
    _file = web.File(<web.BlobPart>[_blob].toJS, 'mayos-workout.png',
        web.FilePropertyBag(type: 'image/png'));
    _downloadUrl = web.URL.createObjectURL(_blob);
  }

  late final web.Blob _blob;
  late final web.File _file;
  late final String _downloadUrl;

  @override
  bool canShare() => web.window.navigator.canShare(
        web.ShareData(files: <web.File>[_file].toJS),
      );

  @override
  Future<void> share() => _waitForShare(web.window.navigator.share(
        web.ShareData(files: <web.File>[_file].toJS),
      ));

  Future<void> _waitForShare(JSPromise<JSAny?> pendingShare) async {
    try {
      await pendingShare.toDart;
    } on web.DOMException catch (error) {
      if (error.name == 'AbortError') {
        throw const WorkoutCardShareDismissed();
      }
      rethrow;
    }
  }

  @override
  void download() {
    final web.HTMLAnchorElement anchor =
        web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = _downloadUrl;
    anchor.download = 'mayos-workout.png';
    anchor.click();
  }

  @override
  void dispose() {
    Timer(const Duration(seconds: 1), () => web.URL.revokeObjectURL(_downloadUrl));
  }
}
