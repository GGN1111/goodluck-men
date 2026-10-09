import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../ingest/ocr_service.dart';

/// T035 — Image intake flow (contract A2): pick/photograph → offline OCR →
/// extracted text handed to the same analysis path as pasted text with
/// `source_type = ocr`. Failure settles in [IntakeFailed] with the
/// preserved attempt so the Home screen can offer the paste fallback
/// instead of fabricating a brief (contract A3 / FR-007).

sealed class ImageIntakeState {
  const ImageIntakeState();
}

final class IntakeIdle extends ImageIntakeState {
  const IntakeIdle();
}

final class IntakeReading extends ImageIntakeState {
  const IntakeReading();
}

final class IntakeReady extends ImageIntakeState {
  const IntakeReady(this.text);

  final String text;
}

final class IntakeFailed extends ImageIntakeState {
  const IntakeFailed(this.result);

  final OcrResult result;
}

typedef ImagePickerFn = Future<String?> Function(ImageSource source);

/// Production picker: local gallery/camera only (zero network egress).
Future<String?> defaultImagePicker(ImageSource source) async {
  final picked = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1920,
    imageQuality: 85,
  );
  return picked?.path;
}

class ImageIntakeController {
  ImageIntakeController({required ImagePickerFn pickImage, OcrService? ocr})
      : _pick = pickImage,
        _ocr = ocr ?? OcrService();

  final ImagePickerFn _pick;
  final OcrService _ocr;

  final ValueNotifier<ImageIntakeState> state =
      ValueNotifier<ImageIntakeState>(const IntakeIdle());

  /// pick → OCR → state. Cancelled picks fall back to idle without error.
  Future<void> capture(ImageSource source) async {
    if (state.value is IntakeReading) return;
    state.value = const IntakeReading();

    String? path;
    try {
      path = await _pick(source);
    } catch (e) {
      state.value = IntakeFailed(
        OcrResult.failure(attempt: 'image_picker', reason: 'pick_error: $e'),
      );
      return;
    }
    if (path == null) {
      state.value = const IntakeIdle();
      return;
    }

    final result = await _ocr.extract(path);
    state.value = result.success
        ? IntakeReady(result.text!)
        : IntakeFailed(result);
  }

  void reset() => state.value = const IntakeIdle();

  void dispose() => state.dispose();
}

/// "Scan image" button: gallery/camera chooser → [ImageIntakeController].
class ScanImageButton extends StatelessWidget {
  const ScanImageButton({
    super.key,
    required this.controller,
    this.enabled = true,
  });

  final ImageIntakeController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: enabled ? () => _pickSource(context) : null,
      icon: const Icon(Icons.photo_camera_outlined),
      label: const Text('Scan image'),
    );
  }

  Future<void> _pickSource(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (source != null) await controller.capture(source);
  }
}
