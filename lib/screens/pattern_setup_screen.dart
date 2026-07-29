import 'package:calls_recording/services/app_lock_service.dart';
import 'package:calls_recording/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:pattern_lock/pattern_lock.dart';

class PatternSetupScreen extends StatefulWidget {
  final AppLockService appLockService;
  final bool isChangingPattern;
  final bool canCancel;
  final VoidCallback? onPatternSaved;

  const PatternSetupScreen({
    super.key,
    required this.appLockService,
    this.isChangingPattern = false,
    this.canCancel = true,
    this.onPatternSaved,
  });

  @override
  State<PatternSetupScreen> createState() => _PatternSetupScreenState();
}

class _PatternSetupScreenState extends State<PatternSetupScreen> {
  List<int>? _firstPattern;
  String? _errorMessage;
  bool _isSaving = false;

  Future<void> _handlePattern(List<int> pattern) async {
    if (_isSaving) return;
    if (pattern.length < 4) {
      setState(() {
        _errorMessage = 'Connect at least 4 dots.';
      });
      return;
    }

    if (_firstPattern == null) {
      setState(() {
        _firstPattern = List<int>.of(pattern);
        _errorMessage = null;
      });
      return;
    }

    if (!_patternsMatch(_firstPattern!, pattern)) {
      setState(() {
        _firstPattern = null;
        _errorMessage = 'Patterns did not match. Draw a new pattern.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await widget.appLockService.savePattern(pattern);
      if (!mounted) return;
      if (widget.onPatternSaved != null) {
        widget.onPatternSaved!();
      } else {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Could not save the pattern securely. Try again.';
      });
    }
  }

  bool _patternsMatch(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final confirming = _firstPattern != null;

    return PopScope(
      canPop: widget.canCancel,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: widget.canCancel,
          title: Text(
            widget.isChangingPattern ? 'Change pattern' : 'Secure this app',
          ),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(
                        Icons.pattern_rounded,
                        color: AppColors.primary,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      confirming
                          ? 'Draw the same pattern again'
                          : 'Create your unlock pattern',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      confirming
                          ? 'Confirm it once so we know you remember it.'
                          : 'This is required before you enter the app. '
                                'Connect at least 4 dots; fingerprint unlock '
                                'will also be available when supported.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _errorMessage == null
                          ? const SizedBox(height: 38)
                          : Container(
                              key: ValueKey(_errorMessage),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.warningSoft,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.warning,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                    ),
                    SizedBox(
                      key: const Key('pattern-setup-grid'),
                      width: 300,
                      height: 300,
                      child: IgnorePointer(
                        ignoring: _isSaving,
                        child: PatternLock(
                          selectedColor: AppColors.primary,
                          notSelectedColor: AppColors.cardBorder,
                          pointRadius: 11,
                          fillPoints: true,
                          relativePadding: 0.7,
                          onInputComplete: _handlePattern,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_isSaving)
                      const CircularProgressIndicator()
                    else if (confirming)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _firstPattern = null;
                            _errorMessage = null;
                          });
                        },
                        child: const Text('Start over'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
