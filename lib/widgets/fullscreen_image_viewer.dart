import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:image_picker/image_picker.dart';

class FullscreenImageViewer extends StatefulWidget {
  final Uint8List imageData;
  final String? heroTag;

  const FullscreenImageViewer({
    super.key,
    required this.imageData,
    this.heroTag,
  });

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  final TransformationController _transformationController = TransformationController();
  TapDownDetails? _doubleTapDetails;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap() {
    if (_transformationController.value != Matrix4.identity()) {
      _transformationController.value = Matrix4.identity();
    } else {
      final position = _doubleTapDetails!.localPosition;
      _transformationController.value = Matrix4.identity()
        ..translate(-position.dx * 2, -position.dy * 2)
        ..scale(3.0);
    }
  }

  Future<void> _saveToGallery() async {
    try {
      // Show loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saving image...'), duration: Duration(seconds: 1)),
      );

      // Save to temporary file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(path.join(tempDir.path, 'zarq_image_${DateTime.now().millisecondsSinceEpoch}.jpg'));
      await tempFile.writeAsBytes(widget.imageData);

      // Save to gallery using gal
      await Gal.putImage(tempFile.path);

      // Delete temp file
      await tempFile.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image saved to gallery'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // print('[FullscreenViewer] Error saving image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _shareImage() async {
    try {
      // Create temporary file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(path.join(tempDir.path, 'zarq_share_${DateTime.now().millisecondsSinceEpoch}.jpg'));
      await tempFile.writeAsBytes(widget.imageData);

      // Share the file
      await Share.shareXFiles(
        [XFile(tempFile.path)],
        text: 'Shared from Zarq Messenger',
      );

      // Clean up temp file after a delay (give share enough time)
      Future.delayed(const Duration(seconds: 5), () {
        tempFile.delete().catchError((e) => print('[FullscreenViewer] Failed to delete temp file: $e'));
      });
    } catch (e) {
      // print('[FullscreenViewer] Error sharing image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageWidget = Image.memory(
      widget.imageData,
      fit: BoxFit.contain,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Image viewer with zoom
            Center(
              child: GestureDetector(
                onDoubleTapDown: _handleDoubleTapDown,
                onDoubleTap: _handleDoubleTap,
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: widget.heroTag != null
                      ? Hero(
                          tag: widget.heroTag!,
                          child: imageWidget,
                        )
                      : imageWidget,
                ),
              ),
            ),

            // Top bar with close button
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.6),
                      Colors.transparent,
                    ],
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.share, color: Colors.white, size: 24),
                      onPressed: _shareImage,
                      tooltip: 'Share',
                    ),
                    IconButton(
                      icon: const Icon(Icons.download, color: Colors.white, size: 24),
                      onPressed: _saveToGallery,
                      tooltip: 'Download',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
