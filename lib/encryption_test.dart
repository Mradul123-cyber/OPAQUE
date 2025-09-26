import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:zarq_messenger/services/SignalService.dart';
import 'services/device_service.dart';
import 'dart:math' as Math;

class EncryptionTest extends StatefulWidget {
  const EncryptionTest({Key? key}) : super(key: key);

  @override
  State<EncryptionTest> createState() => _EncryptionTestState();
}

class _EncryptionTestState extends State<EncryptionTest> {
  String _testResults = '';
  bool _isLoading = false;
  int _selectedTab = 0;

  final TextEditingController _messageController = TextEditingController(
      text: 'Hello, this is a secure encrypted message using Signal Protocol!'
  );
  final TextEditingController _targetUidController = TextEditingController();
  final TextEditingController _targetDeviceIdController = TextEditingController();
  final TextEditingController _ciphertextController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _clearResults();
  }

  Future<void> _testSenderMode() async {
    setState(() {
      _isLoading = true;
      _testResults = 'Encrypting message for target user...\n\n';
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        _updateResults('Error: No authenticated user');
        return;
      }

      String targetUid = _targetUidController.text.trim();
      String targetDeviceIdStr = _targetDeviceIdController.text.trim();
      String testMessage = _messageController.text.trim();

      if (targetUid.isEmpty || targetDeviceIdStr.isEmpty) {
        _updateResults('Error: Please fill in target UID and device ID');
        return;
      }

      int targetDeviceId;
      try {
        targetDeviceId = int.parse(targetDeviceIdStr);
      } catch (e) {
        _updateResults('Error: Invalid device ID format');
        return;
      }

      if (testMessage.isEmpty) testMessage = 'Test encrypted message';

      _updateResults('Current User: ${currentUser.uid.substring(0, 10)}...');
      _updateResults('Target User: ${targetUid.substring(0, 10)}...');
      _updateResults('Target Device: $targetDeviceId');
      _updateResults('');

      // Check encryption readiness
      _updateResults('Checking encryption system...');
      final stats = await SignalService.getEncryptionStats();
      if (stats != null) {
        _updateResults('✓ System ready (Device ${stats['device_id']})');
      } else {
        _updateResults('✗ Failed to get encryption stats');
        return;
      }

      await Future.delayed(Duration(milliseconds: 800));

      // Establish session
      _updateResults('Establishing secure session...');
      bool hasSession = await SignalService.hasSession(recipientUid: targetUid, deviceId: targetDeviceId);

      if (!hasSession) {
        _updateResults('Fetching prekey bundle...');
        final prekeyBundle = await DeviceService.fetchPrekeyBundle(
          targetUid: targetUid,
          deviceId: targetDeviceId,
        );

        if (prekeyBundle == null) {
          _updateResults('✗ Could not fetch prekey bundle');
          _updateResults('Check target UID and device ID');
          return;
        }

        final sessionEstablished = await SignalService.establishSession(
          recipientUid: targetUid,
          prekeyBundle: prekeyBundle,
          deviceId: targetDeviceId,
        );

        if (!sessionEstablished) {
          _updateResults('✗ Session establishment failed');
          return;
        }
        _updateResults('✓ Session established');
      } else {
        _updateResults('✓ Using existing session');
      }

      await Future.delayed(Duration(milliseconds: 800));

      // Encrypt message
      _updateResults('Encrypting message...');
      final encryptedMessage = await SignalService.encryptMessage(
        recipientUid: targetUid,
        plaintext: testMessage,
        deviceId: targetDeviceId,
      );

      if (encryptedMessage != null) {
        _updateResults('✓ Message encrypted successfully');
        _updateResults('Length: ${encryptedMessage.length} characters');
        _updateResults('');
        _updateResults('Encrypted message:');
        _updateResults(encryptedMessage);

        await Clipboard.setData(ClipboardData(text: encryptedMessage));
        _updateResults('');
        _updateResults('✓ Copied to clipboard');
        _updateResults('Share this with the target user for decryption');
      } else {
        _updateResults('✗ Message encryption failed');
      }

    } catch (e) {
      _updateResults('✗ Test failed: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testReceiverMode() async {
    setState(() {
      _isLoading = true;
      _testResults = 'Decrypting message from sender...\n\n';
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        _updateResults('Error: No authenticated user');
        return;
      }

      String senderUid = _targetUidController.text.trim();
      String senderDeviceIdStr = _targetDeviceIdController.text.trim();
      String ciphertext = _ciphertextController.text.trim();

      if (senderUid.isEmpty || senderDeviceIdStr.isEmpty || ciphertext.isEmpty) {
        _updateResults('Error: Please fill in all fields');
        return;
      }

      int senderDeviceId;
      try {
        senderDeviceId = int.parse(senderDeviceIdStr);
      } catch (e) {
        _updateResults('Error: Invalid device ID format');
        return;
      }

      _updateResults('Current User: ${currentUser.uid.substring(0, 10)}...');
      _updateResults('Sender: ${senderUid.substring(0, 10)}...');
      _updateResults('Sender Device: $senderDeviceId');
      _updateResults('');

      // Check decryption readiness
      _updateResults('Checking decryption system...');
      final stats = await SignalService.getEncryptionStats();
      if (stats != null) {
        _updateResults('✓ System ready (Device ${stats['device_id']})');
      } else {
        _updateResults('✗ Failed to get encryption stats');
        return;
      }

      await Future.delayed(Duration(milliseconds: 800));

      // Decrypt message
      _updateResults('Decrypting message...');
      final decryptedMessage = await SignalService.decryptMessage(
        senderUid: senderUid,
        ciphertextB64: ciphertext,
        deviceId: senderDeviceId,
      );

      if (decryptedMessage != null) {
        _updateResults('✓ Message decrypted successfully');
        _updateResults('');
        _updateResults('Decrypted message:');
        _updateResults('"$decryptedMessage"');
        _updateResults('');
        _updateResults('✓ Cross-device encryption working!');
      } else {
        _updateResults('✗ Message decryption failed');
        _updateResults('Check sender UID and device ID');
      }

    } catch (e) {
      _updateResults('✗ Test failed: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testDeviceId() async {
    setState(() {
      _isLoading = true;
      _testResults = 'Testing device ID generation...\n\n';
    });

    try {
      final deviceId1 = await SignalService.getDeviceId();
      _updateResults('Device ID (1st call): $deviceId1');

      final deviceId2 = await SignalService.getDeviceId();
      _updateResults('Device ID (2nd call): $deviceId2');

      _updateResults('Consistent: ${deviceId1 == deviceId2 ? "✓" : "✗"}');
      _updateResults('Not hardcoded: ${deviceId1 != 1 ? "✓" : "✗"}');
      _updateResults('');

      final keyBundle = await SignalService.generateKeyBundle();
      if (keyBundle != null) {
        _updateResults('Key bundle device ID: ${keyBundle['device_id']}');
        _updateResults('Matches: ${keyBundle['device_id'] == deviceId1 ? "✓" : "✗"}');
      }

      _updateResults('');
      _updateResults('✓ Device ID test completed');
      _updateResults('Your device ID: $deviceId1');

    } catch (e) {
      _updateResults('✗ Device ID test failed: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testKeyRotation() async {
    setState(() {
      _isLoading = true;
      _testResults = 'Testing key rotation functionality...\n\n';
    });

    try {
      // Check current rotation status
      _updateResults('Checking current key rotation status...');
      final stats = await SignalService.getEncryptionStats();
      if (stats != null) {
        _updateResults('Current signed prekey ID: ${stats['signed_prekey_id'] ?? 'unknown'}');
        _updateResults('Needs rotation: ${stats['needs_signed_prekey_rotation']}');
        _updateResults('Last rotation: ${stats['last_signed_prekey_rotation'] ?? 'never'}');
      }

      await Future.delayed(Duration(milliseconds: 1000));

      // Test signed prekey rotation
      _updateResults('');
      _updateResults('Triggering signed prekey rotation...');
      final rotationResult = await SignalService.rotateSignedPreKey();
      _updateResults('Rotation result: ${rotationResult ? "✓ Success" : "✗ Failed"}');

      if (!rotationResult) {
        _updateResults('✗ Signed prekey rotation failed');
        return;
      }

      await Future.delayed(Duration(milliseconds: 800));

      // Check new rotation status
      _updateResults('');
      _updateResults('Checking post-rotation status...');
      final newStats = await SignalService.getEncryptionStats();
      if (newStats != null) {
        _updateResults('New signed prekey ID: ${newStats['signed_prekey_id'] ?? 'unknown'}');
        _updateResults('Still needs rotation: ${newStats['needs_signed_prekey_rotation']}');

        // Compare IDs to confirm rotation
        if (stats != null && newStats['signed_prekey_id'] != null && stats['signed_prekey_id'] != null) {
          final oldId = stats['signed_prekey_id'];
          final newId = newStats['signed_prekey_id'];
          _updateResults('ID changed: ${oldId != newId ? "✓ $oldId → $newId" : "✗ No change"}');
        }
      }

      await Future.delayed(Duration(milliseconds: 800));

      // Test one-time prekey generation
      _updateResults('');
      _updateResults('Testing one-time prekey generation...');
      final preKeys = await SignalService.generateAdditionalPreKeys(count: 100);
      if (preKeys.isNotEmpty) {
        _updateResults('✓ Generated ${preKeys.length} new one-time prekeys');
        _updateResults('First prekey ID: ${preKeys.first['key_id']}');
        _updateResults('Last prekey ID: ${preKeys.last['key_id']}');
      } else {
        _updateResults('✗ Failed to generate additional prekeys');
        return;
      }

      await Future.delayed(Duration(milliseconds: 800));

      // Test backend upload
      _updateResults('');
      _updateResults('Testing backend key upload...');
      final deviceId = stats?['device_id'] as int;

      if (deviceId == null) {
        _updateResults('✗ Could not get device ID for upload');
        return;
      }

      // Prepare signed prekey data for upload
      final signedPreKeyData = await SignalService.getCurrentSignedPreKey();

      if (signedPreKeyData == null) {
        _updateResults('✗ Could not get signed prekey data for upload');
        return;
      }

// Upload rotated keys to backend
      final uploadSuccess = await DeviceService.uploadRotatedKeys(
        deviceId: deviceId,
        signedPreKey: signedPreKeyData,
        oneTimePreKeys: preKeys,
      );

      _updateResults('Backend upload: ${uploadSuccess ? "✓ Success" : "✗ Failed"}');

      if (uploadSuccess) {
        _updateResults('✓ Signed prekey uploaded to database');
        _updateResults('✓ ${preKeys.length} one-time prekeys uploaded to database');
      } else {
        _updateResults('✗ Backend upload failed - check server logs');
      }

      _updateResults('');
      _updateResults('✓ Complete key rotation test finished');
      _updateResults('Local rotation: ${rotationResult ? "Working" : "Failed"}');
      _updateResults('One-time prekeys: ${preKeys.isNotEmpty ? "Working" : "Failed"}');
      _updateResults('Backend upload: ${uploadSuccess ? "Working" : "Failed"}');

    } catch (e) {
      _updateResults('✗ Key rotation test failed: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pasteCiphertext() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData != null && clipboardData.text != null) {
        setState(() {
          _ciphertextController.text = clipboardData.text!;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ciphertext pasted from clipboard'))
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to paste: $e'))
      );
    }
  }

  void _updateResults(String message) {
    setState(() {
      _testResults += '$message\n';
    });
  }

  void _clearResults() {
    setState(() {
      _testResults = 'Select a test mode to begin.\n\nNote: For proper testing, use different devices or user accounts.\n\n';
    });
  }

  Widget _buildInputSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Test Configuration',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
            ),
            SizedBox(height: 16),

            TextField(
              controller: _targetUidController,
              decoration: InputDecoration(
                labelText: 'Target User UID',
                hintText: 'Enter Firebase UID',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            SizedBox(height: 12),

            TextField(
              controller: _targetDeviceIdController,
              decoration: InputDecoration(
                labelText: 'Target Device ID',
                hintText: 'Enter device ID number',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.smartphone),
              ),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 12),

            if (_selectedTab == 0) ...[
              TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  labelText: 'Message to Encrypt',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.message),
                ),
                maxLines: 2,
              ),
            ],

            if (_selectedTab == 1) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ciphertextController,
                      decoration: InputDecoration(
                        labelText: 'Encrypted Message',
                        hintText: 'Paste ciphertext here',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock),
                      ),
                      maxLines: 3,
                    ),
                  ),
                  SizedBox(width: 8),
                  IconButton(
                    onPressed: _pasteCiphertext,
                    icon: Icon(Icons.paste),
                    tooltip: 'Paste',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.blue.withOpacity(0.1),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTestButtons() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<int>(
                    segments: [
                      ButtonSegment<int>(
                        value: 0,
                        label: Text('Encrypt'),
                        icon: Icon(Icons.lock),
                      ),
                      ButtonSegment<int>(
                        value: 1,
                        label: Text('Decrypt'),
                        icon: Icon(Icons.lock_open),
                      ),
                      ButtonSegment<int>(
                        value: 2,
                        label: Text('Device'),
                        icon: Icon(Icons.smartphone),
                      ),
                      ButtonSegment<int>(
                        value: 3,
                        label: Text('Rotation'),
                        icon: Icon(Icons.refresh),
                      ),
                    ],
                    selected: {_selectedTab},
                    onSelectionChanged: (Set<int> selection) {
                      setState(() {
                        _selectedTab = selection.first;
                        _clearResults();
                      });
                    },
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading ? null : () {
                  switch (_selectedTab) {
                    case 0:
                      _testSenderMode();
                      break;
                    case 1:
                      _testReceiverMode();
                      break;
                    case 2:
                      _testDeviceId();
                      break;
                    case 3:
                      _testKeyRotation();
                      break;
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedTab == 0
                      ? Colors.blue
                      : _selectedTab == 1
                      ? Colors.orange
                      : _selectedTab == 2
                      ? Colors.green
                      : Colors.purple,
                  foregroundColor: Colors.white,
                ),
                child: _isLoading
                    ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    SizedBox(width: 12),
                    Text('Testing...'),
                  ],
                )
                    : Text(
                  _selectedTab == 0
                      ? 'Run Encryption Test'
                      : _selectedTab == 1
                      ? 'Run Decryption Test'
                      : _selectedTab == 2
                      ? 'Run Device ID Test'
                      : 'Run Key Rotation Test',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
            SizedBox(height: 8),

            TextButton(
              onPressed: _isLoading ? null : _clearResults,
              child: Text('Clear Results'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsSection() {
    return Expanded(
      child: Card(
        elevation: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Test Results',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
              ),
            ),
            Divider(height: 1),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(16.0),
                child: SingleChildScrollView(
                  child: Text(
                    _testResults.isEmpty ? 'No results yet.' : _testResults,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      height: 1.4,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Signal Protocol Test'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildInputSection(),
              SizedBox(height: 16),
              _buildTestButtons(),
              SizedBox(height: 16),
              _buildResultsSection(),
            ],
          ),
        ),
      ),
    );
  }
}