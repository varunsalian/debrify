import 'package:flutter/material.dart';
import '../../../widgets/tv_text_field.dart';

/// Editable keyword Sources header. The view owns the controller and submission.
class SourceKeywordField extends StatelessWidget {
  const SourceKeywordField({
    super.key,
    required this.scheme,
    required this.controller,
    required this.onSubmitted,
  });

  final ColorScheme scheme;
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: TvTextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        onSubmitted: onSubmitted,
        style: TextStyle(color: scheme.onSurface),
        decoration: InputDecoration(
          hintText: 'Search torrents by keyword',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.arrow_forward_rounded),
            onPressed: () => onSubmitted(controller.text),
          ),
          filled: true,
          fillColor: scheme.surfaceContainerHighest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
