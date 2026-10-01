import 'package:flutter/material.dart';
import '../app/library_controller.dart';
import '../ui/components.dart';
import '../ui/theme.dart';

class AccessScreen extends StatefulWidget {
  const AccessScreen({
    super.key,
    required this.controller,
    required this.onRestore,
  });
  final LibraryController controller;
  final VoidCallback onRestore;
  @override
  State<AccessScreen> createState() => _AccessScreenState();
}

class _AccessScreenState extends State<AccessScreen> {
  final _secret = TextEditingController();
  final _confirm = TextEditingController();
  bool _recovery = false, _visible = false;
  String? _error;
  @override
  void dispose() {
    _secret.clear();
    _secret.dispose();
    _confirm.clear();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final value = _secret.text;
    final creating = widget.controller.status == LibraryStatus.absent;
    if (creating && (value.length < 8 || value != _confirm.text)) {
      setState(
        () => _error =
            'Use at least 8 characters and enter the same password twice.',
      );
      return;
    }
    setState(() => _error = null);
    try {
      if (creating) {
        final code = await widget.controller.create(value);
        _secret.clear();
        _confirm.clear();
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => _RecoveryDialog(code: code),
        );
        if (confirmed == true) {
          await widget.controller.finishCreation();
        } else {
          await widget.controller.lock();
        }
      } else {
        await widget.controller.unlock(value, recovery: _recovery);
        _secret.clear();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final creating = widget.controller.status == LibraryStatus.absent;
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 12, 32, 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 44),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    ArchiveMark(size: 32),
                    SizedBox(width: 10),
                    Text(
                      'mut',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 64),
                const Center(
                  child: Icon(
                    Icons.lock_outline,
                    size: 48,
                    color: MutColors.accent,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Your library.\nOnly yours.',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontSize: 32,
                    height: 1.2,
                    letterSpacing: -1.28,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  creating
                      ? 'Create a local encrypted archive.\nNo account or connection required.'
                      : 'Unlock your archive to return to\nyour books and where you left off.',
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.57,
                    color: MutColors.muted,
                  ),
                ),
                const SizedBox(height: 40),
                TextField(
                  controller: _secret,
                  obscureText: !_visible,
                  enableSuggestions: false,
                  autocorrect: false,
                  onSubmitted: (_) => widget.controller.busy ? null : _submit(),
                  decoration: InputDecoration(
                    hintText: _recovery ? 'Recovery code' : 'Archive password',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      tooltip: 'Show or hide secret',
                      onPressed: () => setState(() => _visible = !_visible),
                      icon: Icon(
                        _visible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                if (creating) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirm,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      hintText: 'Confirm password',
                    ),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: widget.controller.busy ? null : _submit,
                    child: widget.controller.busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(creating ? 'Create library' : 'Unlock library'),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: widget.controller.busy
                        ? null
                        : (creating
                              ? widget.onRestore
                              : () => setState(() {
                                  _recovery = !_recovery;
                                  _secret.clear();
                                })),
                    child: Text(
                      creating
                          ? 'Restore a backup'
                          : _recovery
                          ? 'Use password'
                          : 'Use recovery code',
                    ),
                  ),
                ),
                const SizedBox(height: 56),
                const Center(
                  child: Text(
                    'Encrypted on this device',
                    style: TextStyle(color: MutColors.accent, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'No account. No connection required.',
                    style: TextStyle(color: MutColors.muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecoveryDialog extends StatefulWidget {
  const _RecoveryDialog({required this.code});
  final String code;
  @override
  State<_RecoveryDialog> createState() => _RecoveryDialogState();
}

class _RecoveryDialogState extends State<_RecoveryDialog> {
  final _confirmation = TextEditingController();
  @override
  void dispose() {
    _confirmation.clear();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      title: const Text('Save your recovery code'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Write this down somewhere safe. Your password and this code are the only ways to open the archive.',
            ),
            const SizedBox(height: 20),
            Text(
              widget.code,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
            ),
            const SizedBox(height: 16),
            const Text(
              'This code will not be shown again. Enter its last 6 characters to confirm you saved it.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmation,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(hintText: 'Last 6 characters'),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              _confirmation.text ==
                  widget.code.substring(widget.code.length - 6)
              ? () => Navigator.pop(context, true)
              : null,
          child: const Text('I have saved the code'),
        ),
      ],
    ),
  );
}
