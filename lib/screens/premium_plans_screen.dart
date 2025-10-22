import 'package:flutter/material.dart';
import '../services/payment_service.dart';

class PremiumPlansScreen extends StatefulWidget {
  const PremiumPlansScreen({Key? key}) : super(key: key);

  @override
  State<PremiumPlansScreen> createState() => _PremiumPlansScreenState();
}

class _PremiumPlansScreenState extends State<PremiumPlansScreen> {
  bool _isProcessing = false;
  String? _selectedPlanId;
  Map<String, dynamic>? _subscriptionStatus;
  bool _loadingStatus = true;
  List<Map<String, dynamic>> _plans = [];
  bool _loadingPlans = true;
  String? _plansError;

  @override
  void initState() {
    super.initState();
    _loadSubscriptionStatus();
    _loadPlans();
  }

  Future<void> _loadSubscriptionStatus() async {
    try {
      final status = await PaymentService.getSubscriptionStatus();
      setState(() {
        _subscriptionStatus = status;
        _loadingStatus = false;
      });
    } catch (e) {
      setState(() => _loadingStatus = false);
    }
  }

  Future<void> _loadPlans() async {
    try {
      final plans = await PaymentService.getSubscriptionPlans();
      setState(() {
        _plans = plans;
        _loadingPlans = false;
      });
    } catch (e) {
      setState(() {
        _plansError = e.toString();
        _loadingPlans = false;
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _purchasePlan(Map<String, dynamic> plan) async {
    setState(() {
      _isProcessing = true;
      _selectedPlanId = plan['plan_id'];
    });

    try {
      // Create order on backend
      final orderData = await PaymentService.createOrder(plan['plan_id']);

      // Start native Razorpay payment using Kotlin implementation
      final paymentResult = await PaymentService.startNativeRazorpayPayment(
        keyId: orderData['key_id'],
        amount: orderData['amount'],
        currency: orderData['currency'],
        orderId: orderData['order_id'],
        name: 'Zarq Messenger',
        description: plan['name'],
      );

      // Payment successful - verify with backend
      final result = await PaymentService.verifyPayment(
        orderId: paymentResult['order_id'] ?? '',
        paymentId: paymentResult['payment_id'] ?? '',
        signature: paymentResult['signature'] ?? '',
        planId: _selectedPlanId ?? '',
      );

      setState(() => _isProcessing = false);

      if (mounted) {
        await _loadSubscriptionStatus(); // Reload subscription status
        _showSuccessDialog(result['message'] ?? 'Premium activated!');
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        // Only show error if it's a real failure (not cancellation)
        if (!e.toString().contains('cancelled')) {
          _showErrorDialog('Payment failed: $e');
        }
      }
    }
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 32),
            SizedBox(width: 12),
            Text('Success!', style: TextStyle(color: Colors.black)),
          ],
        ),
        content: Text(message, style: const TextStyle(color: Colors.black87)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Go back to settings
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red, size: 32),
            SizedBox(width: 12),
            Text('Error', style: TextStyle(color: Colors.black)),
          ],
        ),
        content: Text(message, style: const TextStyle(color: Colors.black87)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isTablet = screenWidth > 600;
    final maxWidth = isTablet ? 600.0 : screenWidth;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Premium Plans',
          style: TextStyle(
            color: Colors.black,
            fontSize: isTablet ? 22 : 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isProcessing
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      const Color(0xFF6366F1),
                    ),
                  ),
                  SizedBox(height: isTablet ? 24 : 16),
                  Text(
                    'Processing payment...',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: isTablet ? 18 : 16,
                    ),
                  ),
                ],
              ),
            )
          : _loadingPlans
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          const Color(0xFF6366F1),
                        ),
                      ),
                      SizedBox(height: isTablet ? 24 : 16),
                      Text(
                        'Loading plans...',
                        style: TextStyle(
                          color: Colors.black54,
                          fontSize: isTablet ? 18 : 16,
                        ),
                      ),
                    ],
                  ),
                )
              : _plansError != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: isTablet ? 64 : 48,
                          ),
                          SizedBox(height: isTablet ? 24 : 16),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: isTablet ? 48 : 32,
                            ),
                            child: Text(
                              'Failed to load subscription plans',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black87,
                                fontSize: isTablet ? 20 : 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          SizedBox(height: isTablet ? 16 : 12),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _loadingPlans = true;
                                _plansError = null;
                              });
                              _loadPlans();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                horizontal: isTablet ? 32 : 24,
                                vertical: isTablet ? 16 : 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Center(
              child: Container(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: ListView(
                  padding: EdgeInsets.all(isTablet ? 24 : 16),
                  children: [
                    // Current Subscription Status Banner
                    if (_subscriptionStatus?['has_active_subscription'] == true)
                      Container(
                        padding: EdgeInsets.all(isTablet ? 20 : 16),
                        margin: EdgeInsets.only(bottom: isTablet ? 24 : 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF10B981), Color(0xFF059669)],
                          ),
                          borderRadius: BorderRadius.circular(isTablet ? 20 : 16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withOpacity(0.2),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.white,
                                  size: isTablet ? 28 : 24,
                                ),
                                SizedBox(width: isTablet ? 16 : 12),
                                Text(
                                  'Premium Active',
                                  style: TextStyle(
                                    fontSize: isTablet ? 24 : 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: isTablet ? 12 : 8),
                            Text(
                              'Plan: ${_subscriptionStatus?['plan_name'] ?? 'Premium'}',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: isTablet ? 16 : 14,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              _buildExpiryText(),
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: isTablet ? 16 : 14,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Header Section
                    SizedBox(height: isTablet ? 16 : 8),
                    Icon(
                      Icons.workspace_premium,
                      size: isTablet ? 80 : 64,
                      color: const Color(0xFFF59E0B),
                    ),
                    SizedBox(height: isTablet ? 20 : 16),
                    Text(
                      _subscriptionStatus?['has_active_subscription'] == true
                          ? 'Manage Subscription'
                          : 'Upgrade to Premium',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isTablet ? 32 : 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: isTablet ? 12 : 8),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 32 : 16,
                      ),
                      child: Text(
                        'Unlock unlimited AI power and advanced features',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: isTablet ? 18 : 16,
                          color: Colors.black54,
                          height: 1.4,
                        ),
                      ),
                    ),
                    SizedBox(height: isTablet ? 40 : 32),

                    // Free Plan (Current) - only show if not premium
                    if (_subscriptionStatus?['has_active_subscription'] != true)
                      _buildFreePlanCard(isTablet),
                    if (_subscriptionStatus?['has_active_subscription'] != true)
                      SizedBox(height: isTablet ? 20 : 16),

                    // Trial Policy Notice - Only show if there are trial plans available
                    if (_plans.any((plan) => plan['duration_days'] <= 7 && plan['already_used'] != true))
                      Container(
                        padding: EdgeInsets.all(isTablet ? 20 : 16),
                        margin: EdgeInsets.only(bottom: isTablet ? 24 : 20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF6366F1).withOpacity(0.1), Color(0xFF8B5CF6).withOpacity(0.1)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(isTablet ? 16 : 14),
                          border: Border.all(
                            color: Color(0xFF6366F1).withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_rounded,
                              color: Color(0xFF6366F1),
                              size: isTablet ? 28 : 24,
                            ),
                            SizedBox(width: isTablet ? 16 : 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '⚡ One Trial Per User',
                                    style: TextStyle(
                                      fontSize: isTablet ? 18 : 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF6366F1),
                                    ),
                                  ),
                                  SizedBox(height: isTablet ? 8 : 6),
                                  Text(
                                    'You can choose EITHER the 1-day OR 7-day trial. After purchasing one trial, both options will be locked. Choose wisely!',
                                    style: TextStyle(
                                      fontSize: isTablet ? 15 : 13,
                                      color: Colors.black87,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Premium Plans
                    ..._plans.map((plan) => Padding(
                          padding: EdgeInsets.only(
                            bottom: isTablet ? 20 : 16,
                          ),
                          child: _buildPlanCard(plan, isTablet),
                        )),

                    SizedBox(height: isTablet ? 24 : 16),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildFreePlanCard(bool isTablet) {
    return Container(
      padding: EdgeInsets.all(isTablet ? 24 : 20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(isTablet ? 20 : 16),
        border: Border.all(
          color: Colors.grey.shade300,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Free Plan',
                style: TextStyle(
                  fontSize: isTablet ? 24 : 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              SizedBox(width: isTablet ? 12 : 8),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 10 : 8,
                  vertical: isTablet ? 5 : 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(isTablet ? 10 : 8),
                ),
                child: Text(
                  'CURRENT',
                  style: TextStyle(
                    fontSize: isTablet ? 12 : 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isTablet ? 8 : 4),
          Text(
            '₹0 / Forever',
            style: TextStyle(
              fontSize: isTablet ? 28 : 24,
              fontWeight: FontWeight.bold,
              color: Colors.black54,
            ),
          ),
          SizedBox(height: isTablet ? 20 : 16),
          _buildFeature('5 AI requests per day', false, isTablet),
          _buildFeature('5,000 tokens per day', false, isTablet),
          _buildFeature('Basic chat features', false, isTablet),
          _buildFeature('Standard support', false, isTablet),
        ],
      ),
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan, bool isTablet) {
    final isPopular = plan['popular'] == true;
    final alreadyUsed = plan['already_used'] == true;
    final hasActiveSubscription = _subscriptionStatus?['has_active_subscription'] == true;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(isTablet ? 20 : 16),
        gradient: isPopular
            ? LinearGradient(
                colors: [
                  Color(plan['color']).withOpacity(0.1),
                  Color(plan['color']).withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isPopular ? null : Colors.grey.shade50,
        border: Border.all(
          color: isPopular
              ? Color(plan['color']).withOpacity(0.5)
              : Colors.grey.shade300,
          width: isPopular ? 2 : 1.5,
        ),
        boxShadow: isPopular
            ? [
                BoxShadow(
                  color: Color(plan['color']).withOpacity(0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.all(isTablet ? 24 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Plan name
                Text(
                  plan['name'],
                  style: TextStyle(
                    fontSize: isTablet ? 24 : 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                SizedBox(height: isTablet ? 8 : 4),

                // Price
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '₹${plan['price']}',
                      style: TextStyle(
                        fontSize: isTablet ? 36 : 32,
                        fontWeight: FontWeight.bold,
                        color: Color(plan['color']),
                      ),
                    ),
                    SizedBox(width: isTablet ? 6 : 4),
                    Text(
                      '/ ${plan['duration']}',
                      style: TextStyle(
                        fontSize: isTablet ? 18 : 16,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isTablet ? 24 : 20),

                // Features
                ...List.generate(
                  (plan['features'] as List).length,
                  (index) => _buildFeature(
                    plan['features'][index].toString(),
                    true,
                    isTablet,
                  ),
                ),

                SizedBox(height: isTablet ? 24 : 20),

                // Purchase button, Already Used, or Active Subscription indicator
                if (alreadyUsed)
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      vertical: isTablet ? 18 : 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(isTablet ? 14 : 12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          color: Colors.grey.shade600,
                          size: isTablet ? 22 : 20,
                        ),
                        SizedBox(width: isTablet ? 10 : 8),
                        Text(
                          'Trial Already Used',
                          style: TextStyle(
                            fontSize: isTablet ? 18 : 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (hasActiveSubscription)
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                      vertical: isTablet ? 18 : 16,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(isTablet ? 14 : 12),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_clock,
                          color: Colors.orange.shade700,
                          size: isTablet ? 22 : 20,
                        ),
                        SizedBox(width: isTablet ? 10 : 8),
                        Text(
                          'Active Plan Running',
                          style: TextStyle(
                            fontSize: isTablet ? 18 : 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _purchasePlan(plan),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(plan['color']),
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          vertical: isTablet ? 18 : 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(isTablet ? 14 : 12),
                        ),
                        elevation: 2,
                        shadowColor: Color(plan['color']).withOpacity(0.3),
                      ),
                      child: Text(
                        'Upgrade Now',
                        style: TextStyle(
                          fontSize: isTablet ? 18 : 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Popular or Already Used badge
          if (alreadyUsed)
            Positioned(
              top: isTablet ? 16 : 12,
              right: isTablet ? 16 : 12,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 14 : 12,
                  vertical: isTablet ? 7 : 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade500,
                  borderRadius: BorderRadius.circular(isTablet ? 14 : 12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: isTablet ? 14 : 12,
                    ),
                    SizedBox(width: isTablet ? 6 : 4),
                    Text(
                      'USED',
                      style: TextStyle(
                        fontSize: isTablet ? 12 : 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (isPopular)
            Positioned(
              top: isTablet ? 16 : 12,
              right: isTablet ? 16 : 12,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 14 : 12,
                  vertical: isTablet ? 7 : 6,
                ),
                decoration: BoxDecoration(
                  color: Color(plan['color']),
                  borderRadius: BorderRadius.circular(isTablet ? 14 : 12),
                  boxShadow: [
                    BoxShadow(
                      color: Color(plan['color']).withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  'POPULAR',
                  style: TextStyle(
                    fontSize: isTablet ? 12 : 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFeature(String text, bool isPremium, bool isTablet) {
    return Padding(
      padding: EdgeInsets.only(bottom: isTablet ? 14 : 12),
      child: Row(
        children: [
          Icon(
            isPremium ? Icons.check_circle : Icons.check_circle_outline,
            color: isPremium ? Colors.green : Colors.black54,
            size: isTablet ? 22 : 20,
          ),
          SizedBox(width: isTablet ? 14 : 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: isTablet ? 16 : 14,
                color: isPremium ? Colors.black87 : Colors.black54,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _buildExpiryText() {
    final days = _subscriptionStatus?['days_remaining'] ?? 0;
    final hours = _subscriptionStatus?['hours_remaining'] ?? 0;
    final minutes = _subscriptionStatus?['minutes_remaining'] ?? 0;

    List<String> parts = [];

    if (days > 0) {
      parts.add('$days day${days > 1 ? 's' : ''}');
    }
    if (hours > 0) {
      parts.add('$hours hour${hours > 1 ? 's' : ''}');
    }
    if (minutes > 0 || parts.isEmpty) {
      parts.add('$minutes minute${minutes > 1 ? 's' : ''}');
    }

    return 'Expires in ${parts.join(', ')}';
  }
}
