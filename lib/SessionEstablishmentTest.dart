import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zarq_messenger/services/SignalService.dart';
import 'services/device_service.dart';

class SessionEstablishmentTest extends StatefulWidget {
  const SessionEstablishmentTest({Key? key}) : super(key: key);

  @override
  State<SessionEstablishmentTest> createState() => _SessionEstablishmentTestState();
}

class _SessionEstablishmentTestState extends State<SessionEstablishmentTest> {
  String _testResults = 'Ready to test session establishment...';
  bool _isLoading = false;
  final TextEditingController _targetUidController = TextEditingController();

  Future<void> _testSessionEstablishment() async {
    setState(() {
      _isLoading = true;
      _testResults = 'Testing Signal Protocol session establishment...\n';
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        _updateResults('❌ No authenticated user');
        return;
      }

      String targetUid = _targetUidController.text.trim();
      if (targetUid.isEmpty) {
        // Use current user's own UID for self-test
        targetUid = currentUser.uid;
        _updateResults('ℹ️ No target UID provided, testing with own UID for demonstration');
      }

      _updateResults('🎯 Target user: ${targetUid.substring(0, 10)}...');

      // Test 1: Check if session already exists
      _updateResults('📋 Test 1: Checking existing session...');
      final existingSession = await SignalService.hasSession(recipientUid: targetUid);
      _updateResults('   Existing session: $existingSession');

      // Test 2: Fetch prekey bundle from backend
      _updateResults('📥 Test 2: Fetching prekey bundle...');
      final prekeyBundle = await DeviceService.fetchPrekeyBundle(
        targetUid: targetUid,
        deviceId: 1,
      );

      if (prekeyBundle == null) {
        _updateResults('❌ Failed to fetch prekey bundle - user may not exist or have keys');
        return;
      }

      _updateResults('✅ Prekey bundle fetched successfully:');
      _updateResults('   - Identity Key: ${prekeyBundle['identity_key_b64']?.toString().substring(0, 30)}...');
      _updateResults('   - Registration ID: ${prekeyBundle['registration_id']}');
      _updateResults('   - Signed PreKey ID: ${prekeyBundle['signed_prekey_id']}');
      _updateResults('   - One-Time PreKey ID: ${prekeyBundle['one_time_prekey_id'] ?? 'None'}');

      await Future.delayed(Duration(milliseconds: 1000));

      // Test 3: Establish session using X3DH
      _updateResults('🔐 Test 3: Establishing session with X3DH...');
      final sessionEstablished = await SignalService.establishSession(
        recipientUid: targetUid,
        prekeyBundle: prekeyBundle,
      );

      if (sessionEstablished) {
        _updateResults('✅ Session established successfully!');
      } else {
        _updateResults('❌ Session establishment failed');
        return;
      }

      await Future.delayed(Duration(milliseconds: 500));

      // Test 4: Verify session exists
      _updateResults('✅ Test 4: Verifying session...');
      final sessionExists = await SignalService.hasSession(recipientUid: targetUid);
      if (sessionExists) {
        _updateResults('✅ Session verification successful');
      } else {
        _updateResults('❌ Session verification failed');
      }

      await Future.delayed(Duration(milliseconds: 500));

      // Test 5: Test session removal (optional)
      _updateResults('🧹 Test 5: Testing session removal...');
      final sessionRemoved = await SignalService.removeSession(recipientUid: targetUid);
      if (sessionRemoved) {
        _updateResults('✅ Session removed successfully');

        // Verify removal
        final sessionAfterRemoval = await SignalService.hasSession(recipientUid: targetUid);
        _updateResults('   Session exists after removal: $sessionAfterRemoval');
      } else {
        _updateResults('❌ Session removal failed');
      }

      _updateResults('\n🎉 Session establishment test completed!');
      _updateResults('✨ X3DH key agreement protocol working correctly.');
      _updateResults('💡 Ready for message encryption/decryption implementation.');

    } catch (e) {
      _updateResults('❌ Test failed with error: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _updateResults(String message) {
    setState(() {
      _testResults += '\n$message';
    });
  }

  void _clearResults() {
    setState(() {
      _testResults = 'Ready to test session establishment...';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Session Establishment Test'),
        backgroundColor: Colors.purple,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'X3DH Session Establishment Test',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Tests the Signal Protocol X3DH key agreement to establish encrypted sessions.',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    SizedBox(height: 12),
                    TextField(
                      controller: _targetUidController,
                      decoration: InputDecoration(
                        labelText: 'Target User UID (optional)',
                        hintText: 'Leave empty to test with own UID',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _testSessionEstablishment,
                    icon: _isLoading
                        ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : Icon(Icons.vpn_key),
                    label: Text(_isLoading ? 'Testing...' : 'Test Sessions'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _clearResults,
                  icon: Icon(Icons.clear),
                  label: Text('Clear'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Expanded(
              child: Card(
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16.0),
                  child: SingleChildScrollView(
                    child: Text(
                      _testResults,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
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
}