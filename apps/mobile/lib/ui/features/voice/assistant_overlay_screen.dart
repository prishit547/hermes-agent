import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';

import '../../core/atl_theme.dart';
import '../../core/halo_orb.dart';
import '../../../domain/models/message.dart';
import '../chat/view_models/chat_view_model.dart';
import 'voice_view_model.dart';

class AssistantOverlayScreen extends StatefulWidget {
  const AssistantOverlayScreen({super.key});

  @override
  State<AssistantOverlayScreen> createState() => _AssistantOverlayScreenState();
}

class _AssistantOverlayScreenState extends State<AssistantOverlayScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  bool _isKeyboardMode = false;
  final TextEditingController _textCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  static const _channel = MethodChannel('hermes/assistant');

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0.0, 1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _anim,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
    _fade = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _anim,
      curve: Curves.easeOut,
    ));

    _anim.forward();

    // Begin voice session
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<VoiceViewModel>().begin();
      }
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    _textCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _dismissOverlay() async {
    // Release voice resource
    await context.read<VoiceViewModel>().reset();
    
    // Animate slide-down
    await _anim.reverse();
    
    // Call platform channels to pop the native Android activity
    try {
      await _channel.invokeMethod('dismiss');
    } on PlatformException catch (e) {
      debugPrint("Failed to dismiss assistant: $e");
      // Fallback
      if (mounted) {
        SystemNavigator.pop();
      }
    }
  }

  void _submitText(String text) {
    if (text.trim().isEmpty) return;
    _textCtrl.clear();
    _focusNode.unfocus();
    
    // Temporarily halt voice stream while typing
    context.read<VoiceViewModel>().reset();
    
    // Send text turn to ChatViewModel
    final chatVm = context.read<ChatViewModel>();
    chatVm.newChat(); // Start fresh session context for quick assistant overlay
    chatVm.sendText(text);
  }

  @override
  Widget build(BuildContext context) {
    final atl = context.atl;
    final voiceVm = context.watch<VoiceViewModel>();
    final chatVm = context.watch<ChatViewModel>();

    // Determine current text / transcript display
    String displayedLabel = voiceVm.label;
    String displayedTranscript = voiceVm.transcript;

    if (_isKeyboardMode) {
      if (chatVm.isSending) {
        displayedLabel = chatVm.toolStatus.isNotEmpty ? chatVm.toolStatus : 'Thinking…';
        if (chatVm.messages.isNotEmpty && chatVm.messages.last.role == MessageRole.assistant) {
          displayedTranscript = chatVm.messages.last.content;
        } else {
          displayedTranscript = 'Processing request…';
        }
      } else if (chatVm.error != null) {
        displayedLabel = 'Error';
        displayedTranscript = chatVm.error!;
      } else if (chatVm.messages.isNotEmpty) {
        displayedLabel = 'Response';
        displayedTranscript = chatVm.messages.last.content;
      } else {
        displayedLabel = 'Keyboard Input';
        displayedTranscript = 'Type what you want me to do.';
      }
    }

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _dismissOverlay();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            // Top background dismiss trigger
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _dismissOverlay,
                child: AnimatedBuilder(
                  animation: _fade,
                  builder: (_, __) => Container(
                    color: Colors.black.withOpacity(_fade.value * 0.4),
                  ),
                ),
              ),
            ),

            // Sliding bottom panel
            Align(
              alignment: Alignment.bottomCenter,
              child: SlideTransition(
                position: _slide,
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(28),
                    topRight: Radius.circular(28),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        18,
                        24,
                        MediaQuery.of(context).viewInsets.bottom + 28,
                      ),
                      decoration: BoxDecoration(
                        color: atl.frost.withOpacity(0.85),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(28),
                          topRight: Radius.circular(28),
                        ),
                        border: Border(
                          top: BorderSide(color: atl.hairline, width: 1.5),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Grab handle bar
                          Container(
                            width: 38,
                            height: 4,
                            decoration: BoxDecoration(
                              color: atl.text3.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Text status displays
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            child: Text(
                              displayedLabel,
                              key: ValueKey(displayedLabel),
                              textAlign: TextAlign.center,
                              style: atlSerif(
                                size: 24,
                                color: atl.text,
                                style: FontStyle.italic,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 120),
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                child: Text(
                                  displayedTranscript,
                                  key: ValueKey(displayedTranscript),
                                  textAlign: TextAlign.center,
                                  style: atlSans(
                                    size: 16,
                                    color: atl.text2,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),

                          // Main interaction area (Orb vs TextField)
                          AnimatedSize(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOutCubic,
                            child: _isKeyboardMode
                                ? _buildKeyboardInput(atl)
                                : _buildVoiceOrb(voiceVm),
                          ),
                          const SizedBox(height: 28),

                          // Bottom controls bar
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Keyboard / Voice Toggle
                              _iconButton(
                                atl,
                                _isKeyboardMode
                                    ? Icons.mic_none
                                    : Icons.keyboard_alt_outlined,
                                () {
                                  setState(() {
                                    _isKeyboardMode = !_isKeyboardMode;
                                    if (_isKeyboardMode) {
                                      _focusNode.requestFocus();
                                    } else {
                                      _focusNode.unfocus();
                                      context.read<VoiceViewModel>().begin();
                                    }
                                  });
                                },
                              ),
                              // End Session
                              _endButton(_dismissOverlay),
                              // TTS status indicator
                              _iconButton(
                                atl,
                                voiceVm.state == HaloState.speaking
                                    ? Icons.volume_up
                                    : Icons.volume_mute,
                                () {},
                                enabled: false, // passive indicator
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceOrb(VoiceViewModel vm) {
    return GestureDetector(
      onTap: vm.tapOrb,
      child: HaloOrb(state: vm.state, size: 140),
    );
  }

  Widget _buildKeyboardInput(AtlColors atl) {
    return Container(
      decoration: BoxDecoration(
        color: atl.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: atl.hairline),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _textCtrl,
        focusNode: _focusNode,
        style: atlSans(size: 15, color: atl.text),
        textInputAction: TextInputAction.send,
        onSubmitted: _submitText,
        decoration: InputDecoration(
          hintText: 'Type your request...',
          hintStyle: atlSans(size: 15, color: atl.text3),
          border: InputBorder.none,
          suffixIcon: IconButton(
            icon: Icon(Icons.send, color: atl.accent, size: 20),
            onPressed: () => _submitText(_textCtrl.text),
          ),
        ),
      ),
    );
  }

  Widget _iconButton(AtlColors atl, IconData icon, VoidCallback onTap,
      {bool enabled = true}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: atl.surface2.withOpacity(0.6),
          border: Border.all(color: atl.hairline),
        ),
        child: Icon(icon, size: 20, color: enabled ? atl.text : atl.text3),
      ),
    );
  }

  Widget _endButton(VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: AtlColors.danger,
          boxShadow: [
            BoxShadow(
              color: Color(0x66FF6B75),
              blurRadius: 18,
              offset: Offset(0, 6),
              spreadRadius: -2,
            ),
          ],
        ),
        child: const Icon(Icons.call_end, size: 22, color: Colors.white),
      ),
    );
  }
}
