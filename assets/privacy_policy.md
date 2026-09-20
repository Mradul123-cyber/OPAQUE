# Privacy Policy for OPAQUE

**Last Updated:** September 20, 2026

---

## Introduction

Welcome to **OPAQUE**, a secure messaging application developed by an independent developer in India.

Your privacy is our top priority. This Privacy Policy explains how we collect, use, and protect your information when you use OPAQUE.

---

## Information We Collect

### 1. Information You Provide

**Account Information:**
- Phone number, if you use phone sign-in, and email address (including Gmail), if you use email or Google sign-in. Firebase Authentication manages these details; OPAQUE can access them to authenticate and manage your account.
- Firebase user ID, sign-in provider, and verification status.
- A phone-number hash in our database, where a phone number is available, for contact matching and account checks. This does not make your number anonymous to OPAQUE.
- Username, optional display name, and optional profile picture. Google sign-in can also provide your Google profile name and photo.

**Content You Create:**
- Messages (end-to-end encrypted)
- Photos, videos, and files you send (encrypted)
- Voice and video calls (not recorded)

### 2. Automatically Collected Information

**Device Information:**
- Device ID
- Operating system (Android)
- App version
- Device name (for multi-device support)

**Usage Information:**
- Last seen timestamp
- Online/offline status
- Message delivery status (sent, delivered, read)
- In-app call logs for OPAQUE calls (participants, start/end time, duration, voice/video type, and call outcome). These are call metadata, not recordings or your cellular call history.

### 3. Optional Features and Information We Do Not Access

- ❌ Message content (we cannot read your messages due to end-to-end encryption)
- ❌ Payment information (no in-app purchases)
- Location sharing is optional. If you choose to share a location in a message, that location becomes part of the content you send.
- Contact discovery is optional. With your permission, the app reads device contacts and sends phone-number hashes to our server to find matching OPAQUE accounts.
- ❌ Browsing history

---

## How We Use Your Information

We use your information to:

1. **Provide the Service:**
   - Enable account registration and authentication
   - Deliver messages between users
   - Enable voice and video calls
   - Send push notifications for new messages

2. **Improve the Service:**
   - Fix bugs and technical issues
   - Improve app performance
   - Develop new features

3. **Security:**
   - Prevent spam and abuse
   - Detect and prevent unauthorized access
   - Protect against security threats

---

## End-to-End Encryption (E2EE)

**OPAQUE uses the Signal Protocol for end-to-end encryption.**

This means:
- ✅ Only you and the recipient can read your messages
- ✅ Not even OPAQUE servers can decrypt your messages
- ✅ Messages are encrypted on your device before being sent
- ✅ Photos, videos, and files are also encrypted

**What the server stores:**
- Encrypted message content (unreadable without your encryption keys)
- Metadata (sender, recipient, timestamp)
- Message delivery status

**What the server CANNOT see:**
- Your actual message text
- Contents of photos/videos
- What you're discussing

---

## Data Storage and Security

### Where Your Data is Stored

- **Database Server:** PostgreSQL database hosted on secure servers
- **File Storage:** Encrypted media files stored on server storage

### How We Protect Your Data

1. **Encryption in Transit:** All data sent between your device and servers uses TLS/SSL
2. **Encryption at Rest:** Messages and media are stored encrypted
3. **Secure Authentication:** Firebase Authentication with industry-standard security
4. **Access Control:** Only authorized systems can access the database
5. **Regular Updates:** We keep our security systems up to date

### Data Retention

These periods describe scheduled server cleanup, not an exact deletion time or a guarantee of permanent backup.

- **Messages on our servers:** Encrypted message records are scheduled for server cleanup once they are more than 45 days old. Cleanup does not erase messages already saved in your device chat history.
- **Media on our servers:** Server media storage is temporary. Photos and videos may be removed after they are more than 3 days old and recorded as viewed by the sender and recipient. A fixed deletion deadline is not currently guaranteed for every uploaded file. Media may become unavailable for download after server cleanup.
- **Copies on your device:** Messages and media already downloaded or saved on a device remain there after routine server cleanup. Server cleanup does not remotely erase those copies. Media that has not been downloaded before removal may no longer be retrievable. Local deletion, clearing app data, or removing saved files is separate from server cleanup.
- **In-app call history:** Records of calls made through OPAQUE are scheduled for deletion from our servers once they are more than 30 days old. The Calls page loads this history from the server, so deleted records disappear when the history refreshes. OPAQUE does not keep a separate permanent on-device call-history archive.
- **Messages waiting for a recipient to reconnect:** If a recipient is offline (for example, their phone has no internet connection), encrypted messages can wait on our servers for delivery when they reconnect. These are sometimes called offline messages. Delivery does not necessarily immediately erase the server record; queued records linked to messages are removed by the same 45-day message cleanup. Messages may therefore expire before a recipient reconnects.
- **Deletion requests:** You can delete messages using the options available in the app or email us to request account deletion. Routine server cleanup and account deletion cannot remove copies another person has already saved or exported.

---

## Third-Party Services

We use the following third-party services:

### 1. Firebase (Google)
**Used for:** User authentication, push notifications

**Data shared:**
- Firebase UID (unique identifier)
- Device push token
- Authentication information

**Privacy Policy:** https://firebase.google.com/support/privacy

### 2. Firebase Cloud Messaging (FCM)
**Used for:** Sending push notifications

**Data shared:**
- Device token
- Notification content (encrypted)

**Privacy Policy:** https://policies.google.com/privacy

---

## Your Rights and Choices

### You Have the Right To:

1. **Access Your Data:**
   - View your profile information
   - Export your message history (coming soon)

2. **Delete Your Data:**
   - Delete individual messages
   - Delete conversations
   - Request account deletion by emailing opaquelabs.in@gmail.com. Copies saved by other people are not removed by your account-deletion request.

3. **Control Notifications:**
   - Enable/disable push notifications
   - Customize notification settings

4. **Control Privacy:**
   - Choose who can see your online status
   - Choose who can see your profile picture
   - Control read receipts

### How to Exercise Your Rights:

- **Delete Account:** Email opaquelabs.in@gmail.com with the subject "Account deletion" and your OPAQUE username. We will guide you through ownership verification. Never send your password or one-time verification codes.
- **Delete Messages:** Long press message → Delete
- **Privacy Settings:** Settings → Privacy

---

## Data Sharing

**We do NOT sell, rent, or share your personal information with third parties for their marketing purposes.**

We may share information only in these limited circumstances:

1. **With Your Consent:** When you explicitly agree
2. **Legal Requirements:** If required by law, court order, or government request
3. **Service Providers:** With trusted partners who help operate the service (all under strict agreements)
4. **Safety and Security:** To protect against fraud, abuse, or security threats

---

## Children's Privacy

**Age Requirement:**
- Users must be at least 13 years old to use OPAQUE
- Users under 18 must have parental/guardian permission

**We do not knowingly collect information from children under 13.**

If we discover that a child under 13 has created an account, we will delete it immediately.

Parents/guardians can contact us at **opaquelabs.in@gmail.com** if they believe their child has provided us with information.

---

## International Users

OPAQUE is developed in India and complies with Indian data protection laws.

Your information may be processed by OPAQUE and its service providers in countries other than the country where you live.

---

## Changes to This Privacy Policy

We may update this Privacy Policy from time to time. We will notify you of significant changes by:
- Updating the "Last Updated" date
- Sending an in-app notification
- Posting a notice in the app

Continued use of the app after changes means you accept the updated policy.

---

## Contact Us

If you have questions, concerns, or requests regarding this Privacy Policy or your data:

**Email:** opaquelabs.in@gmail.com

**Developer:** OPAQUE (Independent Developer, India)

We will respond to your inquiry within 7 business days.

---

## Your Consent

By using OPAQUE, you consent to this Privacy Policy and agree to its terms.

If you have concerns about this policy, contact us at opaquelabs.in@gmail.com before continuing. You can stop using OPAQUE and request account deletion at any time.

---

**OPAQUE**

*Your messages. Zero access. Total privacy.*
