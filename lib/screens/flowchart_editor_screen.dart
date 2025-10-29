import 'package:flutter/material.dart';
import 'package:flutter_flow_chart/flutter_flow_chart.dart';
import 'package:provider/provider.dart';
import '../services/user_settings_provider.dart';
import 'dart:ui' as ui;

class FlowchartEditorScreen extends StatefulWidget {
  final String? initialFlowchartJson;

  const FlowchartEditorScreen({
    super.key,
    this.initialFlowchartJson,
  });

  @override
  State<FlowchartEditorScreen> createState() => _FlowchartEditorScreenState();
}

class _FlowchartEditorScreenState extends State<FlowchartEditorScreen> {
  late Dashboard dashboard;
  String selectedElement = 'rectangle';

  @override
  void initState() {
    super.initState();

    final userSettings = Provider.of<UserSettingsProvider>(context, listen: false);
    final isDark = userSettings.notesScreenStyle == 'dark';

    // Load existing flowchart if provided
    if (widget.initialFlowchartJson != null && widget.initialFlowchartJson!.isNotEmpty) {
      try {
        // Load the dashboard from JSON
        dashboard = Dashboard.fromJson(widget.initialFlowchartJson!);
      } catch (e) {
        print('Error loading flowchart: $e');
        dashboard = Dashboard(
          defaultArrowStyle: ArrowStyle.curve,
        );
      }
    } else {
      dashboard = Dashboard(
        defaultArrowStyle: ArrowStyle.curve,
      );
    }

    // Set grid background parameters
    dashboard.setGridBackgroundParams(
      GridBackgroundParams(
        gridColor: isDark ? Colors.white.withOpacity(0.1) : Colors.grey.withOpacity(0.15),
        gridThickness: 1.0,
        gridSquare: 20.0,
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      ),
    );
  }

  void _addElement(String kind) {
    final element = FlowElement(
      position: const Offset(100, 100),
      size: const Size(120, 80),
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

  void _clearAll() {
    setState(() {
      dashboard.removeAllElements();
    });
  }

  @override
  Widget build(BuildContext context) {
    final userSettings = Provider.of<UserSettingsProvider>(context);
    final isDark = userSettings.notesScreenStyle == 'dark';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.close_rounded,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Flowchart Editor',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.delete_outline_rounded,
              color: isDark ? Colors.redAccent : Colors.red,
            ),
            onPressed: _clearAll,
            tooltip: 'Clear all',
          ),
          IconButton(
            icon: Icon(
              Icons.check_rounded,
              color: isDark ? Colors.greenAccent : Colors.green,
            ),
            onPressed: () {
              // Return the flowchart JSON
              try {
                final jsonData = dashboard.toJson();
                Navigator.pop(context, jsonData);
              } catch (e) {
                print('Error saving flowchart: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error saving flowchart: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            tooltip: 'Save',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildShapeButton(
                    'rectangle',
                    Icons.crop_square_rounded,
                    'Rectangle',
                    isDark,
                  ),
                  const SizedBox(width: 8),
                  _buildShapeButton(
                    'diamond',
                    Icons.change_history_rounded,
                    'Diamond',
                    isDark,
                  ),
                  const SizedBox(width: 8),
                  _buildShapeButton(
                    'oval',
                    Icons.circle_outlined,
                    'Oval',
                    isDark,
                  ),
                  const SizedBox(width: 8),
                  _buildShapeButton(
                    'storage',
                    Icons.storage_rounded,
                    'Storage',
                    isDark,
                  ),
                  const SizedBox(width: 8),
                  _buildShapeButton(
                    'parallelogram',
                    Icons.view_stream_rounded,
                    'Parallelogram',
                    isDark,
                  ),
                ],
              ),
            ),
          ),

          // Instructions
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.blueAccent.withOpacity(0.1)
                  : Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark
                    ? Colors.blueAccent.withOpacity(0.3)
                    : Colors.blue.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: isDark ? Colors.blueAccent : Colors.blue,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Tap shapes above to add • Drag to move • Tap & hold to edit • Connect shapes by dragging from dots',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white70 : Colors.black87,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Flowchart Canvas
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox.expand(
                  child: FlowChart(
                    dashboard: dashboard,
                    onDashboardTapped: ((context, position) {
                      // Optional: Add element at tapped position
                    }),
                    onDashboardLongTapped: ((context, position) {}),
                    onDashboardSecondaryTapped: ((context, position) {}),
                    onElementPressed: (context, position, element) {
                      // Show element edit dialog
                      _showEditElementDialog(element, isDark);
                    },
                    onElementLongPressed: (context, position, element) {},
                    onElementSecondaryTapped: (context, position, element) {},
                    onHandlerPressed: (context, position, handler, element) {},
                    onHandlerLongPressed: (context, position, handler, element) {},
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShapeButton(String kind, IconData icon, String label, bool isDark) {
    final isSelected = selectedElement == kind;

    return InkWell(
      onTap: () {
        setState(() {
          selectedElement = kind;
        });
        _addElement(kind);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isSelected
                ? (isDark
                    ? [Colors.blueAccent.withOpacity(0.3), Colors.blue.withOpacity(0.2)]
                    : [Colors.blue.withOpacity(0.2), Colors.lightBlue.withOpacity(0.1)])
                : (isDark
                    ? [Colors.white.withOpacity(0.05), Colors.white.withOpacity(0.02)]
                    : [Colors.grey.shade100, Colors.grey.shade50]),
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? (isDark ? Colors.blueAccent : Colors.blue)
                : (isDark ? Colors.white.withOpacity(0.1) : Colors.grey.shade300),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? (isDark ? Colors.blueAccent : Colors.blue)
                  : (isDark ? Colors.white70 : Colors.black87),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? (isDark ? Colors.blueAccent : Colors.blue)
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditElementDialog(FlowElement element, bool isDark) {
    final textController = TextEditingController(text: element.text);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Edit Element',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textController,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  labelText: 'Text',
                  labelStyle: TextStyle(
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? Colors.blueAccent : Colors.blue,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  dashboard.removeElement(element);
                });
                Navigator.pop(context);
              },
              child: Text(
                'Delete',
                style: TextStyle(
                  color: isDark ? Colors.redAccent : Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  element.setText(textController.text);
                });
                Navigator.pop(context);
              },
              child: Text(
                'Save',
                style: TextStyle(
                  color: isDark ? Colors.greenAccent : Colors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}
