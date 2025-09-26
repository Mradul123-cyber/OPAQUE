import 'package:flutter/material.dart';
import 'package:zarq_messenger/services/SignalService.dart';
import 'package:flutter/material.dart';

class SignalTestPage extends StatefulWidget {
  const SignalTestPage({Key? key}) : super(key: key);

  @override
  State<SignalTestPage> createState() => _SignalTestPageState();
}

class _SignalTestPageState extends State<SignalTestPage> {
  String _testResults = 'Ready to test Signal Protocol setup...';
  bool _isLoading = false;

  Future<void> _runTests() async {
    setState(() {
      _isLoading = true;
      _testResults = 'Running Signal Protocol tests...\n';
    });

    try {
      // Test 1: Ping test
      _updateResults('🔍 Testing method channel connection...');
      final pingResult = await SignalService.ping();
      if (pingResult == 'Signal pong') {
        _updateResults('✅ Method channel working: $pingResult');
      } else {
        _updateResults('❌ Method channel failed: $pingResult');
        return;
      }

      await Future.delayed(Duration(milliseconds: 500));

      // Test 2: Check if keys already exist
      _updateResults('🔑 Checking for existing keys...');
      final hasKeys = await SignalService.hasKeys();
      _updateResults('📝 Keys exist: $hasKeys');

      await Future.delayed(Duration(milliseconds: 500));

      // Test 3: Generate keys (or show existing info)
      if (!hasKeys) {
        _updateResults('🔨 Generating new Signal Protocol keys...');
        final keyBundle = await SignalService.generateKeyBundle();

        if (keyBundle != null) {
          _updateResults('✅ Key generation successful!');
          _updateResults('📊 Key Bundle Info:');
          _updateResults('   - Registration ID: ${keyBundle['registration_id']}');
          _updateResults('   - Signed PreKey ID: ${keyBundle['signed_prekey_id']}');
          _updateResults('   - Identity Key: ${keyBundle['identity_key_b64']?.toString().substring(0, 30)}...');
          _updateResults('   - One-Time PreKeys: ${(keyBundle['one_time_prekeys'] as List?)?.length ?? 0}');
        } else {
          _updateResults('❌ Key generation failed');
          return;
        }
      } else {
        _updateResults('ℹ️ Using existing keys...');

        // Get registration ID from existing keys
        final regId = await SignalService.getRegistrationId();
        if (regId != null) {
          _updateResults('📝 Existing Registration ID: $regId');
        }
      }

      await Future.delayed(Duration(milliseconds: 500));

      // Test 4: Verify keys exist after generation
      _updateResults('✅ Verifying key storage...');
      final hasKeysAfter = await SignalService.hasKeys();
      if (hasKeysAfter) {
        _updateResults('✅ Keys successfully stored and verified');
      } else {
        _updateResults('❌ Key storage verification failed');
      }

      await Future.delayed(Duration(milliseconds: 500));

      // Test 5: Test unimplemented method (should fail gracefully)
      _updateResults('🧪 Testing unimplemented methods...');
      final bundleResult = await SignalService.testGetPreKeyBundle();
      _updateResults('📝 PreKey bundle test: ${bundleResult != null ? "Unexpected success" : "Expected failure (not implemented)"}');

      _updateResults('\n🎉 Signal Protocol key generation test completed!');
      _updateResults('✨ Keys are ready for session establishment.');
      _updateResults('💡 Next step: Implement session management and encryption.');

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
      _testResults = 'Ready to test Signal Protocol setup...';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Signal Protocol Test'),
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
                      'Signal Protocol Setup Test',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'This will test if our Signal Protocol method channel is properly set up.',
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
                    onPressed: _isLoading ? null : _runTests,
                    icon: _isLoading
                        ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : Icon(Icons.play_arrow),
                    label: Text(_isLoading ? 'Testing...' : 'Run Tests'),
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