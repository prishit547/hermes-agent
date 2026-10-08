import 'package:flutter/material.dart';

import '../atl_theme.dart';
import '../atl_tokens.dart';

/// Labelled text field with the app's surface-2 chrome.
///
/// Owns a single stable [TextEditingController] for its lifetime. This replaces
/// the `TextEditingController.fromValue(_valueOf(...))` pattern in settings,
/// which rebuilt a fresh controller on every frame — fragile and prone to
/// fighting the keyboard/IME. External [value] changes are reconciled in
/// [didUpdateWidget] without disturbing the cursor mid-typing.
class AtlField extends StatefulWidget {
  const AtlField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint = '',
    this.obscure = false,
    this.keyboardType = TextInputType.text,
    this.autofillHints,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String hint;
  final bool obscure;
  final TextInputType keyboardType;
  final Iterable<String>? autofillHints;

  @override
  State<AtlField> createState() => _AtlFieldState();
}

class _AtlFieldState extends State<AtlField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  late bool _hidden = widget.obscure;

  @override
  void didUpdateWidget(AtlField old) {
    super.didUpdateWidget(old);
    // Reconcile only genuine external changes (e.g. a programmatic reset),
    // never on every rebuild — and keep the caret at the end.
    if (widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label,
            style: AtlType.label(color: atl.text2, weight: FontWeight.w600)),
        const SizedBox(height: AtlSpace.sm),
        Container(
          decoration: BoxDecoration(
            color: atl.surface2,
            borderRadius: AtlRadius.smAll,
            border: Border.all(color: atl.hairline),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  onChanged: widget.onChanged,
                  obscureText: _hidden,
                  keyboardType: widget.keyboardType,
                  autofillHints: widget.autofillHints,
                  style: AtlType.body(color: atl.text),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: widget.hint,
                    hintStyle: AtlType.body(color: atl.text3),
                    isDense: true,
                  ),
                ),
              ),
              if (widget.obscure)
                IconButton(
                  onPressed: () => setState(() => _hidden = !_hidden),
                  icon: Icon(_hidden ? Icons.visibility_off : Icons.visibility,
                      size: 18, color: atl.text3),
                  visualDensity: VisualDensity.compact,
                  tooltip: _hidden ? 'Show' : 'Hide',
                ),
            ],
          ),
        ),
      ],
    );
  }
}
