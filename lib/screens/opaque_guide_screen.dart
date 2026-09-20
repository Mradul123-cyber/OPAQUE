import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'opaque_guide_content.dart';
import '../widgets/opaque_toast.dart';

/// Shared guide layout for the overview and existing tutorial entry points.
class OpaqueGuideScreen extends StatefulWidget {
  const OpaqueGuideScreen({super.key, this.initialTopic = -1});
  final int initialTopic;

  @override
  State<OpaqueGuideScreen> createState() => _OpaqueGuideScreenState();
}

class _OpaqueGuideScreenState extends State<OpaqueGuideScreen> {
  late int _topic = widget.initialTopic;
  bool _hindi = false;
  final _scroll = ScrollController();
  final Set<int> _expanded = {0};
  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _bg => _dark ? const Color(0xFF19202A) : Colors.white;
  Color get _ink => _dark ? const Color(0xFFE0E6EF) : const Color(0xFF202127);
  Color get _muted => _dark ? const Color(0xFFA0ACBC) : const Color(0xFF737D8B);
  Color get _soft => _dark ? const Color(0xFF252F3D) : const Color(0xFFF3F4F7);
  Color get _line => _dark ? const Color(0xFF303947) : const Color(0xFFE9ECF0);
  Color get _blue => _dark ? const Color(0xFF8AAFE4) : const Color(0xFF507FC3);
  String _t(String en, String hi) => _hindi ? hi : en;
  String _localized(dynamic pair) => pair[_hindi ? 1 : 0] as String;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _open(int topic) {
    setState(() => _topic = topic);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _back() {
    if (_topic >= 0) {
      _open(-1);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Text _text(
    String text, {
    double size = 12,
    Color? color,
    FontWeight weight = FontWeight.w400,
    double height = 1.7,
    double? spacing,
  }) => Text(
    text,
    style: GoogleFonts.inter(
      fontSize: size,
      color: color ?? _ink,
      fontWeight: weight,
      height: height,
      letterSpacing: spacing,
    ),
  );

  IconData _icon(String name) => switch (name) {
    'lock' => Icons.lock_outline_rounded,
    'friends' => Icons.people_outline_rounded,
    'backup' => Icons.restore_rounded,
    'signal' => Icons.sync_rounded,
    'phone' => Icons.smartphone_rounded,
    'chat' => Icons.chat_bubble_outline_rounded,
    'key' => Icons.key_outlined,
    _ => Icons.info_outline_rounded,
  };

  Widget _symbol(String name, {bool inDiagram = false}) => Container(
    width: 39,
    height: 39,
    decoration: BoxDecoration(
      color: inDiagram ? _bg : _soft,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(_icon(name), size: 21, color: _blue),
  );

  Widget _surface({
    required Widget child,
    required VoidCallback onTap,
    double radius = 12,
    bool filled = false,
  }) => Material(
    color: filled ? _soft : Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: filled ? BorderSide(color: _line) : BorderSide.none,
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(onTap: onTap, child: child),
  );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _topic < 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _topic >= 0) _open(-1);
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          surfaceTintColor: Colors.transparent,
          foregroundColor: _ink,
          elevation: 0,
          toolbarHeight: 62,
          leading: IconButton(
            onPressed: _back,
            tooltip: _t('Back', 'वापस'),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          centerTitle: true,
          title: Semantics(
            label: 'Opaque',
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 19,
                    height: 22,
                    child: CustomPaint(painter: _GuideMark(_ink, _bg)),
                  ),
                  const SizedBox(width: 3),
                  _text(
                    'PAQUE',
                    size: 19,
                    weight: FontWeight.w700,
                    spacing: 2.5,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton(
                onPressed: () => setState(() => _hindi = !_hindi),
                style: TextButton.styleFrom(
                  foregroundColor: _ink,
                  backgroundColor: _soft,
                  side: BorderSide(color: _line),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                child: _text(_hindi ? 'English' : 'हिंदी', size: 11),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: _line),
          ),
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(23, 26, 23, 28),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: _topic < 0 ? _overview() : _detail(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _overview() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _text(
        _t('How Opaque works', 'Opaque कैसे काम करता है'),
        size: 25,
        weight: FontWeight.w600,
        height: 1.25,
        spacing: -.8,
      ),
      const SizedBox(height: 9),
      _text(
        _t(
          'Your conversations, connections and privacy. Explained simply.',
          'आपकी बातचीत, दोस्ती और गोपनीयता। सरल शब्दों में।',
        ),
        color: _muted,
      ),
      const SizedBox(height: 23),
      _surface(
        onTap: () => _open(0),
        radius: 17,
        filled: true,
        child: Padding(
          padding: const EdgeInsets.all(19),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 19, color: _blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _text(
                      _t('PRIVACY, EXPLAINED', 'गोपनीयता को समझें'),
                      size: 10,
                      color: _blue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _text(
                _t(
                  'What happens when you hit send?',
                  'संदेश भेजने पर क्या होता है?',
                ),
                size: 17,
                weight: FontWeight.w600,
                spacing: -.3,
                height: 1.4,
              ),
              const SizedBox(height: 5),
              _text(
                _t(
                  'Follow a message from your phone to your friend’s.',
                  'अपने फोन से दोस्त तक संदेश का सफर देखें।',
                ),
                color: _muted,
              ),
              const SizedBox(height: 17),
              Row(
                children: [
                  Expanded(
                    child: _text(
                      _t(
                        'Explore private conversations',
                        'निजी बातचीत को समझें',
                      ),
                      size: 11,
                      color: _blue,
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: _blue, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 27),
      _text(
        _t('EXPLORE THE GUIDES', 'गाइड देखें'),
        size: 9,
        color: _muted,
        spacing: 1.5,
      ),
      const SizedBox(height: 10),
      for (int i = 1; i < opaqueGuides.length; i++) _guideRow(i),
      const SizedBox(height: 25),
      Row(
        children: [
          Icon(Icons.lock_outline_rounded, size: 14, color: _muted),
          const SizedBox(width: 8),
          Expanded(
            child: _text(
              _t(
                'Know your app. Stay in control.',
                'अपने ऐप को जानें। नियंत्रण अपने पास रखें।',
              ),
              size: 10,
              color: _muted,
            ),
          ),
        ],
      ),
    ],
  );

  Widget _guideRow(int index) {
    final g = opaqueGuides[index];
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: _surface(
        onTap: () => _open(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Row(
            children: [
              _symbol(g['icon'] as String),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _text(
                      _localized(g['title']),
                      size: 13,
                      weight: FontWeight.w600,
                    ),
                    const SizedBox(height: 3),
                    _text(_localized(g['sub']), size: 11, color: _muted),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: _muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail() {
    final g = opaqueGuides[_topic];
    final nodes = g['nodes'] as List<dynamic>;
    final steps = g['steps'] as List<dynamic>;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _text(
          '${_t('HOW OPAQUE WORKS', 'OPAQUE कैसे काम करता है')} / 0${_topic + 1}',
          size: 10,
          color: _blue,
        ),
        const SizedBox(height: 14),
        _text(
          _localized(g['title']),
          size: 25,
          weight: FontWeight.w600,
          height: 1.25,
          spacing: -.8,
        ),
        const SizedBox(height: 9),
        _text(_localized(g['sub']), color: _muted),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 22),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 15),
          decoration: BoxDecoration(
            color: _soft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _line),
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (int i = 0; i < nodes.length; i++) ...[
                    if (i > 0)
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 15,
                        color: _muted,
                      ),
                    Expanded(
                      child: Column(
                        children: [
                          _symbol(nodes[i][0] as String, inDiagram: true),
                          const SizedBox(height: 8),
                          Text(
                            nodes[i][_hindi ? 2 : 1] as String,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              height: 1.5,
                              color: _ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: _line),
              const SizedBox(height: 14),
              Text(
                _localized(g['caption']),
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  height: 1.7,
                  color: _muted,
                ),
              ),
            ],
          ),
        ),
        for (int i = 0; i < steps.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _line)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _text('0${i + 1}', size: 11, color: _blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _text(
                        steps[i][_hindi ? 1 : 0] as String,
                        size: 13,
                        weight: FontWeight.w600,
                      ),
                      const SizedBox(height: 4),
                      _text(
                        steps[i][_hindi ? 3 : 2] as String,
                        size: 11,
                        color: _muted,
                        height: 1.8,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (_topic == 3) _technicalDetails(),
        Container(
          margin: const EdgeInsets.only(top: 23),
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: _blue, width: 2)),
          ),
          child: _text(_localized(g['note']), size: 11, color: _muted),
        ),
        const SizedBox(height: 24),
        _surface(
          filled: true,
          onTap: () => _open(_topic == 3 ? -1 : _topic + 1),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: _text(
                    _topic == 3
                        ? _t('Back to all guides', 'सभी गाइड पर वापस')
                        : '${_t('Next: ', 'अगला: ')}${_localized(opaqueGuides[_topic + 1]['title'])}',
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 20, color: _ink),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _technicalDetails() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 26),
      _text(
        _t('THE TECHNICAL DETAILS', 'तकनीकी जानकारी'),
        size: 9,
        color: _muted,
        spacing: 1.5,
      ),
      const SizedBox(height: 7),
      _text(
        _t(
          'Explore the terms behind the protocol. Tap any topic to expand.',
          'प्रोटोकॉल के तकनीकी शब्द समझें। जानकारी खोलने के लिए किसी विषय पर टैप करें।',
        ),
        size: 11,
        color: _muted,
      ),
      const SizedBox(height: 13),
      for (int i = 0; i < opaqueEncryptionTerms.length; i++) _term(i),
      const SizedBox(height: 17),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          _reference('X3DH', 'x3dh'),
          _reference('Double Ratchet', 'doubleratchet'),
          _reference('Sesame', 'sesame'),
        ],
      ),
    ],
  );

  Widget _term(int i) {
    final term = opaqueEncryptionTerms[i];
    final open = _expanded.contains(i);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            expanded: open,
            child: _surface(
              onTap: () => setState(() {
                open ? _expanded.remove(i) : _expanded.add(i);
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 15),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _text(
                            term[0] as String,
                            size: 12,
                            weight: FontWeight.w600,
                          ),
                          if (!_hindi)
                            _text(term[1] as String, size: 9, color: _muted),
                        ],
                      ),
                    ),
                    Icon(
                      open ? Icons.remove_rounded : Icons.add_rounded,
                      size: 19,
                      color: _blue,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.only(right: 10, bottom: 16),
              child: _text(
                term[_hindi ? 3 : 2] as String,
                size: 11,
                color: _muted,
                height: 1.85,
              ),
            ),
        ],
      ),
    );
  }

  Widget _reference(String label, String path) => TextButton(
    style: TextButton.styleFrom(
      foregroundColor: _blue,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      minimumSize: const Size(48, 48),
    ),
    onPressed: () async {
      try {
        final opened = await launchUrl(
          Uri.parse('https://signal.org/docs/specifications/$path/'),
          mode: LaunchMode.externalApplication,
        );
        if (!opened) _linkFailed();
      } catch (_) {
        _linkFailed();
      }
    },
    child: _text('$label ↗', size: 10, color: _blue),
  );

  void _linkFailed() {
    if (!mounted) return;
    OpaqueToast.error(
      context,
      _t(
        'Unable to open reference. Try again.',
        'लिंक नहीं खुल सका। कृपया फिर कोशिश करें।',
      ),
    );
  }
}

class _GuideMark extends CustomPainter {
  const _GuideMark(this.ink, this.background);
  final Color ink, background;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      7.5,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    canvas.drawLine(
      Offset(5, size.height),
      const Offset(14, 0),
      Paint()
        ..color = background
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_GuideMark old) =>
      old.ink != ink || old.background != background;
}
