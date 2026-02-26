import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config/theme.dart';
import 'attachment_picker.dart';

class MessageInput extends StatefulWidget {
  final void Function(String content,
      {String? contentType, String? attachmentUrl}) onSend;

  const MessageInput({super.key, required this.onSend});

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  Future<void> _pickCamera() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      widget.onSend(
        'Sent a photo',
        contentType: 'image',
        attachmentUrl: image.path,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          color: isDark
              ? AppTheme.darkSurface.withValues(alpha: 0.7)
              : Colors.white.withValues(alpha: 0.7),
          child: SafeArea(
            top: false,
            child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.add, color: AppTheme.tealGreen),
              onPressed: () => _showAttachmentPicker(context),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        maxLines: 4,
                        minLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Type a message',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.camera_alt_outlined,
                          color: AppTheme.tealGreen, size: 22),
                      onPressed: _pickCamera,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppTheme.tealGreen,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(
                  _hasText ? Icons.send : Icons.mic,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: _hasText ? _send : null,
              ),
            ),
          ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAttachmentPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => AttachmentPicker(
        onSelected: (type, path) {
          Navigator.pop(context);
          widget.onSend(
            'Sent a $type',
            contentType: type,
            attachmentUrl: path,
          );
        },
      ),
    );
  }
}
