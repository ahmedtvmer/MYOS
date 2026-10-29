import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:web/web.dart' as web;

import 'workout_photo_adapter.dart';

Future<Uint8List> prepareWorkoutPhoto(XFile photo) async {
  final web.Blob blob = await _pickerBlob(photo);
  try {
    return await _prepareFromBitmap(blob);
  } on Object {
    return _prepareFromHtmlImage(blob);
  }
}

Future<web.Blob> _pickerBlob(XFile photo) async {
  try {
    final web.Response response = await web.window.fetch(photo.path.toJS).toDart;
    if (!response.ok) throw StateError('Picker photo could not be fetched');
    return await response.blob().toDart;
  } on Object {
    final Uint8List bytes = await photo.readAsBytes();
    return web.Blob(<web.BlobPart>[bytes.toJS].toJS,
        web.BlobPropertyBag(type: photo.mimeType ?? 'image/jpeg'));
  }
}

Future<Uint8List> _prepareFromBitmap(web.Blob blob) async {
  final web.ImageBitmap upright = await web.window.createImageBitmap(blob,
      web.ImageBitmapOptions(imageOrientation: 'from-image')).toDart;
  late final web.ImageBitmap resized;
  try {
    final WorkoutPhotoSize target =
        workoutPhotoResizeSize(upright.width, upright.height);
    resized = await web.window.createImageBitmap(upright,
        web.ImageBitmapOptions(resizeWidth: target.width,
            resizeHeight: target.height, resizeQuality: 'high')).toDart;
  } finally {
    upright.close();
  }
  try {
    try {
      final web.OffscreenCanvas canvas =
          web.OffscreenCanvas(resized.width, resized.height);
      final web.OffscreenCanvasRenderingContext2D? context =
          canvas.getContext('2d') as web.OffscreenCanvasRenderingContext2D?;
      if (context == null) throw StateError('Canvas 2D context is unavailable');
      context.drawImage(resized, 0, 0, resized.width, resized.height);
      final web.Blob jpeg = await canvas.convertToBlob(
          web.ImageEncodeOptions(type: 'image/jpeg', quality: 0.9)).toDart;
      return (await jpeg.arrayBuffer().toDart).toDart.asUint8List();
    } on Object {
      return await _encodeHtmlCanvas(resized, resized.width, resized.height);
    }
  } finally {
    resized.close();
  }
}

Future<Uint8List> _prepareFromHtmlImage(web.Blob blob) async {
  final String url = web.URL.createObjectURL(blob);
  try {
    final web.HTMLImageElement image =
        web.document.createElement('img') as web.HTMLImageElement;
    image.src = url;
    await image.decode().toDart;
    final WorkoutPhotoSize target =
        workoutPhotoResizeSize(image.naturalWidth, image.naturalHeight);
    return await _encodeHtmlCanvas(image, target.width, target.height);
  } finally {
    web.URL.revokeObjectURL(url);
  }
}

Future<Uint8List> _encodeHtmlCanvas(
    web.CanvasImageSource source, int width, int height) async {
  final web.HTMLCanvasElement canvas =
      web.document.createElement('canvas') as web.HTMLCanvasElement;
  canvas.width = width;
  canvas.height = height;
  final web.CanvasRenderingContext2D? context =
      canvas.getContext('2d') as web.CanvasRenderingContext2D?;
  if (context == null) throw StateError('Canvas 2D context is unavailable');
  context.drawImage(source, 0, 0, width, height);
  final Completer<web.Blob> encoded = Completer<web.Blob>();
  canvas.toBlob(((web.Blob? jpeg) {
    if (jpeg == null) {
      encoded.completeError(StateError('Canvas JPEG encoding failed'));
    } else {
      encoded.complete(jpeg);
    }
  }).toJS, 'image/jpeg', 0.9.toJS);
  final web.Blob jpeg = await encoded.future;
  return (await jpeg.arrayBuffer().toDart).toDart.asUint8List();
}
