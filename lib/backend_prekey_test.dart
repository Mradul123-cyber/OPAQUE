import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/device_service.dart';

class BackendPreKeyTest extends StatefulWidget {
  const BackendPreKeyTest({Key? key}) : super(key: key);

  @override
  State<BackendPreKeyTest> createState() => _BackendPreKeyTestState();
}

class _BackendPreKeyTestState extends State<BackendPreKeyTest> {
  String _testResults = 'Ready to test backend prekey bundle storage/retrieval...';
  bool _isLoading = false;

  Future<void> _testBackendFlow() async {
    setState(() {
      _isLoading = true;
      _testResults = 'Testing backend prekey bundle flow...\n';
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        _updateResults('❌ No authenticated user');
        return;
      }

      final currentUid = currentUser.uid;
      _updateResults('🔍 Testing with user: ${currentUid.substring(0, 10)}...');

      // Declare variable outside try blocks so it's accessible later
      Map<String, dynamic>? ownBundle;

      // Test 1: Try to fetch current user's own prekey bundle
      _updateResults('📥 Test 1: Fetching own prekey bundle...');

      try {
        ownBundle = await DeviceService.fetchPrekeyBundle(
          targetUid: currentUid,
          deviceId: 1,
        );

        if (ownBundle != null) {
          _updateResults('✅ Successfully retrieved own prekey bundle:');
          _updateResults('   - Identity Key: ${ownBundle['identity_key_b64']?.toString().substring(0, 30)}...');
          _updateResults('   - Registration ID: ${ownBundle['registration_id']}');
          _updateResults('   - Signed PreKey ID: ${ownBundle['signed_prekey_id']}');
          _updateResults('   - One-Time PreKey ID: ${ownBundle['one_time_prekey_id'] ?? 'None consumed'}');
          _updateResults('   - Device ID: ${ownBundle['device_id']}');

          // Check if one-time prekey was consumed
          if (ownBundle['one_time_prekey_id'] != null) {
            _updateResults('📝 One-time prekey consumed (good - server is managing keys)');
          }
        } else {
          _updateResults('❌ Own prekey bundle not found');
          _updateResults('   This could mean:');
          _updateResults('   - Keys weren\'t uploaded properly');
          _updateResults('   - Backend API endpoint issue');
          _updateResults('   - Database storage problem');
        }
      } catch (e) {
        _updateResults('❌ Error fetching own bundle: $e');
      }

      await Future.delayed(Duration(milliseconds: 1000));

      // Test 2: Try to fetch a non-existent user's bundle
      _updateResults('\n📥 Test 2: Fetching non-existent user bundle...');

      try {
        final fakeBundle = await DeviceService.fetchPrekeyBundle(
          targetUid: 'fake_user_uid_12345',
          deviceId: 1,
        );

        if (fakeBundle == null) {
          _updateResults('✅ Correctly returned null for non-existent user');
        } else {
          _updateResults('⚠️ Unexpectedly found bundle for fake user');
        }
      } catch (e) {
        _updateResults('📝 Expected error for fake user: ${e.toString().contains('404') ? 'Good (404)' : e}');
      }

      await Future.delayed(Duration(milliseconds: 1000));

      // Test 3: Check key consumption (fetch again to see if one-time key changes)
      _updateResults('\n📥 Test 3: Testing one-time key consumption...');

      try {
        final bundle2 = await DeviceService.fetchPrekeyBundle(
          targetUid: currentUid,
          deviceId: 1,
        );

        if (bundle2 != null) {
          final firstKeyId = ownBundle?['one_time_prekey_id'];
          final secondKeyId = bundle2['one_time_prekey_id'];

          if (firstKeyId != secondKeyId) {
            _updateResults('✅ One-time keys are being consumed properly');
            _updateResults('   First fetch key ID: $firstKeyId');
            _updateResults('   Second fetch key ID: $secondKeyId');
          } else {
            _updateResults('📝 Same one-time key returned (may be expected behavior)');
          }
        }
      } catch (e) {
        _updateResults('❌ Error in consumption test: $e');
      }

      _updateResults('\n🎉 Backend prekey bundle test completed!');
      _updateResults('💡 Ready to implement session establishment if tests passed.');

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
      _testResults = 'Ready to test backend prekey bundle storage/retrieval...';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Backend PreKey Test'),
        backgroundColor: Colors.blue,
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
                      'Backend PreKey Bundle Test',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Tests if your Go backend can store and retrieve Signal Protocol prekey bundles.',
                      style: TextStyle(color: Colors.grey[600]),
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
                    onPressed: _isLoading ? null : _testBackendFlow,
                    icon: _isLoading
                        ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : Icon(Icons.cloud_sync),
                    label: Text(_isLoading ? 'Testing...' : 'Test Backend'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
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