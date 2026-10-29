import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:web/web.dart' as web;

import 'workout_photo_adapter.dart';

/// Browser-side decode + downscale so Flutter (CanvasKit/WASM) never has to
/// decode a full camera photo. Decode and EXIF-rotate first, then size from the
/// upright bitmap: computing the target from the raw sensor dimensions would
/// squash every rotated (portrait) phone photo. Works for any format the
/// browser can decode, not only JPEG.
Future<Uint8List> prepareWorkoutPhoto(XFile photo) async {
  final Uint8List bytes = await photo.readAsBytes();
  final web.Blob fileBlob = web.Blob(<web.BlobPart>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: photo.mimeType ?? 'image/jpeg'));
  final web.ImageBitmap upright = await web.window.createImageBitmap(fileBlob,
      web.ImageBitmapOptions(imageOrientation: 'from-image')).toDart;
  web.ImageBitmap? resized;
  try {
    final WorkoutPhotoSize target = workoutPhotoResizeSize(upright.width, upright.height);
    resized = await web.window.createImageBitmap(upright,
        web.ImageBitmapOptions(resizeWidth: target.width, resizeHeight: target.height,
            resizeQuality: 'high')).toDart;
    try {
      final web.OffscreenCanvas canvas = web.OffscreenCanvas(resized.width, resized.height);
      final web.OffscreenCanvasRenderingContext2D? context =
          canvas.getContext('2d') as web.OffscreenCanvasRenderingContext2D?;
      if (context == null) throw StateError('Canvas 2D context is unavailable');
      context.drawImage(resized, 0, 0, resized.width, resized.height);
      final web.Blob jpeg = await canvas.convertToBlob(
          web.ImageEncodeOptions(type: 'image/jpeg', quality: 0.9)).toDart;
      return (await jpeg.arrayBuffer().toDart).toDart.asUint8List();
    } on Object {
      return await _encodeHtmlCanvas(resized);
    }
  } finally {
    upright.close();
    resized?.close();
  }
}

Future<Uint8List> _encodeHtmlCanvas(web.ImageBitmap bitmap) async {
  final web.HTMLCanvasElement canvas =
      web.document.createElement('canvas') as web.HTMLCanvasElement;
  canvas.width = bitmap.width;
  canvas.height = bitmap.height;
  final web.CanvasRenderingContext2D context =
      canvas.getContext('2d') as web.CanvasRenderingContext2D;
  context.drawImage(bitmap, 0, 0, bitmap.width, bitmap.height);
  final Completer<web.Blob> encoded = Completer<web.Blob>();
  canvas.toBlob(((web.Blob? blob) {
    if (blob == null) {
      encoded.completeError(StateError('Canvas JPEG encoding failed'));
    } else {
      encoded.complete(blob);
    }
  }).toJS, 'image/jpeg', 0.9.toJS);
  final web.Blob jpeg = await encoded.future;
  return (await jpeg.arrayBuffer().toDart).toDart.asUint8List();
}
