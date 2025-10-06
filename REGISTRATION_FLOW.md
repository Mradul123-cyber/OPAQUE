# Registration Flow & Incomplete Registration Handling

## Complete Registration Flow

### Normal Flow (User Completes Everything)

```
1. SignupScreen
   ↓ (User enters email, password, username)
2. Firebase Account Created
   ↓
3. ProfileSetupScreen
   ↓ (User adds display name, avatar - or clicks "Skip")
4. RegisterScreen
   ↓ (Creates backend profile, registers device)
5. HomeScreen
   ✅ Fully Registered
```

## Handling Incomplete Registration

### Scenario 1: User Cancels During Profile Setup

**What happens:**
- User is on ProfileSetupScreen
- User clicks the ❌ (close) button in app bar
- Confirmation dialog appears: "Cancel Registration?"

**Options:**
1. **No** → Returns to ProfileSetupScreen
2. **Yes, Cancel** →
   - Deletes Firebase account
   - Returns to LoginScreen
   - User must sign up again from scratch

**Code location:** `profile_setup_screen.dart:38-80`

### Scenario 2: User Closes App During Profile Setup

**What happens:**
- User completes signup
- User is on ProfileSetupScreen
- User closes/kills the app (without completing profile setup)

**On Next App Open:**

1. **Firebase Auth State Check** (`main.dart:175-192`)
   - Firebase detects user is still logged in
   - Sends user to AuthWrapper

2. **Backend Profile Check** (`main.dart:435-436, 528-532`)
   - AuthWrapper tries to initialize services
   - Checks if backend profile exists via `/profiles/me`
   - **Profile NOT found** → Returns `false`

3. **Redirect to Complete Registration** (`main.dart:940-965`)
   - Since `isReady = false`
   - App shows ProfileSetupScreen again
   - User can:
     - Complete profile setup → Continue to RegisterScreen
     - Cancel registration → Delete account and start over

**Code flow:**
```dart
// AuthWrapper build method (main.dart:940-965)
final bool isReady = snapshot.data ?? false;
if (isReady) {
  return const HomeScreen();  // Profile exists
} else {
  // No backend profile - complete registration
  return ProfileSetupScreen(
    user: widget.user,
    onSetupComplete: (displayName, avatarUrl) {
      // Navigate to RegisterScreen
    },
  );
}
```

### Scenario 3: User Closes App During Registration (RegisterScreen)

**What happens:**
- User completes ProfileSetupScreen
- User is on RegisterScreen
- User closes/kills the app

**On Next App Open:**

Same as Scenario 2:
- Backend profile check fails
- User redirected to ProfileSetupScreen
- Must complete registration flow again

**Note:** RegisterScreen also has a "Cancel and Go Back" button that deletes the Firebase account

## User Interface Elements

### ProfileSetupScreen Buttons

1. **❌ Close Button (App Bar Left)**
   - Opens confirmation dialog
   - Deletes Firebase account on confirm
   - Returns to login screen

2. **Skip Button (App Bar Right)**
   - Skips profile customization
   - Proceeds to RegisterScreen with default values
   - User can add profile info later in settings

3. **Continue Button (Bottom)**
   - Validates display name (if provided)
   - Proceeds to RegisterScreen with user's choices

### RegisterScreen Buttons

1. **← Back Button (App Bar)**
   - Returns to ProfileSetupScreen
   - Allows user to modify display name or avatar
   - Maintains registration progress

2. **Complete Registration Button**
   - Creates backend profile
   - Registers device encryption keys
   - Completes registration flow

3. **Cancel and Go Back Button**
   - Shows confirmation dialog
   - Deletes Firebase account on confirm
   - Returns to login screen

## Technical Implementation

### Backend Profile Check

**Endpoint:** `GET /profiles/me`

**Function:** `_checkIfProfileExists()` (main.dart:668-673)
```dart
Future<bool> _checkIfProfileExists() async {
  final token = await widget.user.getIdToken(true);
  final url = Uri.parse('http://192.168.29.81:8080/profiles/me');
  final response = await http.get(url, headers: {'Authorization': 'Bearer $token'});
  return response.statusCode == 200;  // true if profile exists
}
```

**Returns:**
- `true` - Backend profile exists → User is fully registered
- `false` - No backend profile → User needs to complete registration

### State Management

**Firebase Auth State:**
- Managed by Firebase SDK
- Persists across app restarts
- User.delete() removes it

**Backend Profile State:**
- Stored in PostgreSQL database
- Created only when RegisterScreen completes
- Linked to Firebase UID

**Incomplete Registration Detection:**
```
Firebase User Exists: ✅
Backend Profile Exists: ❌
Result: Incomplete registration - redirect to ProfileSetupScreen
```

## Security Considerations

1. **Firebase Account Cleanup:**
   - Cancelled registrations delete Firebase account
   - No orphaned Firebase users without backend profiles

2. **Token Validation:**
   - Backend always validates Firebase token
   - Ensures user owns the Firebase account

3. **Profile Completion:**
   - Users cannot access app without backend profile
   - Encryption keys only registered after profile creation

## User Experience

### Good UX Decisions

✅ **Back Navigation Between Screens**
- User can go back from RegisterScreen to ProfileSetupScreen
- Allows modifying display name or avatar before final registration
- Maintains Firebase account and progress

✅ **Cancel with Confirmation**
- Prevents accidental account deletion
- Clear warning about consequences

✅ **Resume Incomplete Registration**
- User doesn't lose progress if they close app
- Same flow continues from where they left

✅ **Skip Option**
- Users can skip profile customization
- Reduces friction in signup flow

✅ **Clear Visual Indicators**
- ❌ icon clearly indicates "cancel"
- ← back arrow allows editing profile
- "Skip" explicitly states it's optional

### Navigation Flow

**Forward Flow:**
```
SignupScreen → ProfileSetupScreen → RegisterScreen → Complete
                     ↓ Skip                              ↓
                RegisterScreen                      HomeScreen
```

**Backward Flow (User can go back):**
```
RegisterScreen → ← Back Button → ProfileSetupScreen
                                       ↓
                                  Edit & Continue → RegisterScreen
```

**Cancel Flow:**
```
ProfileSetupScreen → ❌ Cancel → Confirmation → Delete Account → LoginScreen
RegisterScreen → Cancel Button → Confirmation → Delete Account → LoginScreen
```

### Potential Improvements (Future)

1. **Save Draft Profile:**
   - Store display name/avatar temporarily
   - Pre-fill when user returns

2. **Progress Indicator:**
   - Show "Step 1 of 2: Profile Setup"
   - Help user understand where they are

3. **Time Limit:**
   - Auto-delete incomplete registrations after 24 hours
   - Send reminder email before deletion

## Testing Checklist

- [ ] User can cancel during ProfileSetupScreen
- [ ] Cancelled accounts are deleted from Firebase
- [ ] User redirected to login after cancellation
- [ ] User can close app during profile setup
- [ ] Reopening app resumes from ProfileSetupScreen
- [ ] User can complete registration after closing app
- [ ] User can close app during RegisterScreen
- [ ] Reopening app resumes registration flow
- [ ] **Back button in RegisterScreen returns to ProfileSetupScreen**
- [ ] **User can modify profile info and proceed again**
- [ ] **Profile changes are preserved when returning to RegisterScreen**
- [ ] Skip button works correctly
- [ ] Profile data persists when provided
- [ ] Backend profile check works correctly
- [ ] Error handling for network issues
- [ ] Cancel button in RegisterScreen still deletes account
- [ ] Both cancel methods (ProfileSetup and Register) work correctly
