import '../widgets/notes_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_flow_chart/flutter_flow_chart.dart';
import 'package:provider/provider.dart';
import '../services/user_settings_provider.dart';

class FlowchartEditorScreen extends StatefulWidget {
  final String? initialFlowchartJson;

  const FlowchartEditorScreen({super.key, this.initialFlowchartJson});

  @override
  State<FlowchartEditorScreen> createState() => _FlowchartEditorScreenState();
}

class _FlowchartEditorScreenState extends State<FlowchartEditorScreen> {
  late Dashboard dashboard;
  String selectedElement = 'rectangle';

  @override
  void initState() {
    super.initState();

    final userSettings = Provider.of<UserSettingsProvider>(
      context,
      listen: false,
    );
    final isDark = userSettings.isDarkMode;

    // Load existing flowchart if provided
    if (widget.initialFlowchartJson != null &&
        widget.initialFlowchartJson!.isNotEmpty) {
      try {
        // Load the dashboard from JSON
        dashboard = Dashboard.fromJson(widget.initialFlowchartJson!);
      } catch (e) {
        print('Error loading flowchart: $e');
        dashboard = Dashboard(defaultArrowStyle: ArrowStyle.curve);
      }
    } else {
      dashboard = Dashboard(defaultArrowStyle: ArrowStyle.curve);
    }

    final c = NotesColors(context);
    // Set grid background parameters
    dashboard.setGridBackgroundParams(
      GridBackgroundParams(
        gridColor: isDark
            ? Colors.white.withOpacity(0.1)
            : Colors.grey.withOpacity(0.15),
        gridThickness: 1.0,
        gridSquare: 20.0,
        backgroundColor: c.soft,
      ),
    );
    _initialSnapshot = dashboard.toJson();
  }

  void _addElement(String kind) {
    final c = NotesColors(context);
    final element = FlowElement(
      textColor: c.ink,
      textSize: 13,
      backgroundColor: c.surface,
      borderColor: const Color(0xFFB2C7E4),
      borderThickness: 1,
      position: const Offset(100, 100),
      size: const Size(150, 62),
      text: 'New ${kind.capitalize()}',
      kind: _getElementKind(kind),
      handlers: [
        Handler.topCenter,
        Handler.bottomCenter,
        Handler.leftCenter,
        Handler.rightCenter,
      ],
    );

    setState(() {
      dashboard.addElement(element);
    });
  }

  ElementKind _getElementKind(String kind) {
    switch (kind) {
      case 'diamond':
        return ElementKind.diamond;
      case 'rectangle':
        return ElementKind.rectangle;
      case 'oval':
        return ElementKind.oval;
      case 'storage':
        return ElementKind.storage;
      case 'parallelogram':
        return ElementKind.parallelogram;
      default:
        return ElementKind.rectangle;
    }
  }

  bool _leaving = false;
  bool _saving = false;
  late String _initialSnapshot;

  Future<void> _leave() async {
    bool changed = true;
    try {
      changed = dashboard.toJson() != _initialSnapshot;
    } catch (_) {}
    if (changed) {
      final discard = await showNotesConfirmation(
        context,
        title: 'Discard changes?',
        body:
            'Your latest flowchart changes haven’t been saved. Leave without saving them?',
        confirm: 'Discard',
        danger: true,
        icon: Icons.account_tree_outlined,
      );
      if (!mounted || !discard) return;
    }
    if (!mounted) return;
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    try {
      final save = await showNotesConfirmation(
        context,
        title: 'Save flowchart?',
        body:
            'Keep this flowchart attached to your note. Save the note to keep your changes.',
        confirm: 'Save flowchart',
        icon: Icons.account_tree_outlined,
      );
      if (!mounted || !save) return;
      final json = dashboard.toJson();
      setState(() => _leaving = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, json);
      });
    } catch (_) {
      if (mounted)
        await showNotesConfirmation(
          context,
          title: 'Couldn’t save flowchart',
          body:
              'Your diagram is still here. Close this message and try saving again.',
          confirm: 'Continue editing',
          icon: Icons.account_tree_outlined,
        );
    } finally {
      _saving = false;
    }
  }

  Future<void> _clearAll() async {
    final clear = await showNotesConfirmation(
      context,
      title: 'Clear flowchart?',
      body:
          'Remove all shapes and connections from this diagram? The note’s text will stay.',
      confirm: 'Clear all',
      danger: true,
      icon: Icons.account_tree_outlined,
    );
    if (mounted && clear) setState(() => dashboard.removeAllElements());
  }

  @override
  Widget build(BuildContext context) {
    context.watch<UserSettingsProvider>();
    final c = NotesColors(context);
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: c.surface,
        appBar: AppBar(
          backgroundColor: c.surface,
          foregroundColor: c.ink,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            tooltip: 'Back to note',
            onPressed: _leave,
            icon: Icon(Icons.arrow_back, size: 20, color: c.muted),
          ),
          title: Text('Flowchart', style: c.text(15, bold: true)),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: c.line),
          ),
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
                child: Text(
                  'A diagram for this note.',
                  style: c.text(12, muted: true),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: [
                    for (final item in [
                      ('rectangle', Icons.crop_square_rounded, 'Rectangle'),
                      ('diamond', Icons.change_history_rounded, 'Diamond'),
                      ('oval', Icons.circle_outlined, 'Oval'),
                      ('storage', Icons.storage_rounded, 'Storage'),
                      (
                        'parallelogram',
                        Icons.view_stream_rounded,
                        'Parallelogram',
                      ),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() => selectedElement = item.$1);
                            _addElement(item.$1);
                          },
                          icon: Icon(item.$2, size: 16),
                          label: Text(
                            item.$3,
                            style: const TextStyle(fontSize: 11),
                          ),
                          style: TextButton.styleFrom(
                            backgroundColor: c.soft,
                            foregroundColor: selectedElement == item.$1
                                ? c.blue
                                : c.muted,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
                child: Text(
                  'Add a shape, drag to move, tap to edit. Drag between dots to connect shapes.',
                  style: c.text(10, muted: true).copyWith(height: 1.6),
                ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 22),
                  decoration: BoxDecoration(
                    color: c.soft,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.line),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: FlowChart(
                      dashboard: dashboard,
                      onDashboardTapped: (context, position) {},
                      onDashboardLongTapped: (context, position) {},
                      onDashboardSecondaryTapped: (context, position) {},
                      onElementPressed: (context, position, element) =>
                          _editElement(element),
                      onElementLongPressed: (context, position, element) {},
                      onElementSecondaryTapped: (context, position, element) {},
                      onHandlerPressed:
                          (context, position, handler, element) {},
                      onHandlerLongPressed:
                          (context, position, handler, element) {},
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: NotesButton(
                        label: 'Clear all',
                        onPressed: _clearAll,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: NotesButton(
                        label: 'Save flowchart',
                        primary: true,
                        onPressed: _save,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editElement(FlowElement element) async {
    final action = await showDialog<String>(
      context: context,
      builder: (_) => _FlowNodeDialog(element: element),
    );
    if (!mounted) return;
    if (action == 'delete') {
      final remove = await showNotesConfirmation(
        context,
        title: 'Delete shape?',
        body: 'Remove this shape and its connections from the flowchart?',
        confirm: 'Delete',
        danger: true,
        icon: Icons.account_tree_outlined,
      );
      if (mounted && remove) setState(() => dashboard.removeElement(element));
    } else if (action == 'saved') {
      setState(() {});
    }
  }
}

class _FlowNodeDialog extends StatefulWidget {
  const _FlowNodeDialog({required this.element});
  final FlowElement element;
  @override
  State<_FlowNodeDialog> createState() => _FlowNodeDialogState();
}

class _FlowNodeDialogState extends State<_FlowNodeDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.element.text,
  );
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = NotesColors(context);
    return NotesDialog(
      title: 'Edit shape',
      icon: Icons.account_tree_outlined,
      body: TextField(
        controller: _text,
        maxLines: 3,
        style: c.text(12),
        decoration: c.field('Shape text'),
      ),
      actions: [
        NotesButton(
          label: 'Delete',
          danger: true,
          onPressed: () => Navigator.pop(context, 'delete'),
        ),
        NotesButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
        NotesButton(
          label: 'Save',
          primary: true,
          onPressed: () {
            widget.element.setText(_text.text);
            Navigator.pop(context, 'saved');
          },
        ),
      ],
    );
  }
}

extension StringExtension on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
