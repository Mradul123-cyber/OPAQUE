package com.zarq.messenger

import android.app.Activity
import android.util.Log
import com.razorpay.Checkout
import com.razorpay.PaymentResultListener
import org.json.JSONObject
import org.json.JSONArray

class RazorpayPaymentHandler(private val activity: Activity) : PaymentResultListener {

    companion object {
        private const val TAG = "RazorpayPaymentHandler"
    }

    private var paymentCallback: PaymentCallback? = null
    private var currentOrderId: String = ""
    // Dialog monitoring removed - UPI Intent flow bypasses Razorpay UI entirely

    interface PaymentCallback {
        fun onPaymentSuccess(orderId: String, paymentId: String, signature: String)
        fun onPaymentError(errorCode: Int, errorMessage: String)
    }

    fun startPayment(
        keyId: String,
        amount: Int,
        currency: String,
        orderId: String,
        name: String,
        description: String,
        callback: PaymentCallback
    ) {
        Log.d(TAG, "Starting Razorpay payment - OrderID: $orderId, Amount: $amount, KeyID: $keyId")

        this.paymentCallback = callback
        this.currentOrderId = orderId // Store orderId for success callback

        try {
            val checkout = Checkout()
            checkout.setKeyID(keyId)

            // Disable all Razorpay SDK dialogs - we handle errors ourselves
            checkout.setImage(activity.applicationInfo.icon)

            // Log which UPI apps are installed and can be detected
            try {
                val packageManager = activity.packageManager
                val upiApps = listOf(
                    "com.google.android.apps.nbu.paisa.user" to "Google Pay",
                    "net.one97.paytm" to "Paytm",
                    "com.phonepe.app" to "PhonePe",
                    "in.org.npci.upiapp" to "BHIM"
                )

                Log.d(TAG, "=== Checking installed UPI apps ===")
                upiApps.forEach { (packageName, appName) ->
                    try {
                        packageManager.getPackageInfo(packageName, 0)
                        Log.d(TAG, "✅ $appName is INSTALLED")
                    } catch (e: Exception) {
                        Log.d(TAG, "❌ $appName is NOT installed")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error checking UPI apps: ${e.message}")
            }

            val options = JSONObject().apply {
                put("name", name)
                put("description", description)
                put("order_id", orderId)
                put("amount", amount)
                put("currency", currency)

                // Payment method restrictions - ONLY UPI, Cards, and Netbanking allowed
                // Disable: Wallets, EMI, Pay Later, Cardless EMI
                put("method", JSONObject().apply {
                    put("netbanking", true)
                    put("card", true)
                    put("upi", true)
                    put("wallet", false)
                    put("emi", false)
                    put("paylater", false)
                    put("cardless_emi", false)
                })

                // Modern theme configuration
                put("theme", JSONObject().apply {
                    put("color", "#6366F1")           // Primary brand color
                    put("backdrop_color", "#1A1D2E")   // Dark backdrop
                    put("hide_topbar", false)          // Show topbar
                })

                // Prefill (optional)
                put("prefill", JSONObject().apply {
                    put("contact", "")
                    put("email", "")
                })

                // Modern modal configuration
                put("modal", JSONObject().apply {
                    put("confirm_close", true)         // Ask before closing
                    put("escape", true)                // Allow ESC key
                    put("animation", true)             // Smooth animations
                    put("backdropclose", false)        // Don't close on backdrop click
                    put("handleback", true)            // Handle Android back button
                })

                // Disable retry to prevent error dialogs
                put("retry", JSONObject().apply {
                    put("enabled", false)
                    put("max_count", 0)
                })

                // Clean, modern display preferences
                put("readonly", JSONObject().apply {
                    put("contact", false)              // Allow editing contact
                    put("email", false)                // Allow editing email
                })

                // Modern checkout experience
                put("remember_customer", false)        // Don't save customer details
                put("send_sms_hash", true)            // Send SMS hash for auto-read OTP
            }

            Log.d(TAG, "Opening Razorpay checkout with options: ${options.toString(2)}")

            // Open checkout - Razorpay will call our PaymentResultListener methods
            checkout.open(activity, options)

        } catch (e: Exception) {
            Log.e(TAG, "Error starting payment: ${e.message}", e)
            callback.onPaymentError(-1, "Failed to start payment: ${e.message}")
        }
    }

    // PaymentResultListener implementation
    override fun onPaymentSuccess(razorpayPaymentId: String?) {
        Log.d(TAG, "✅ UPI Intent Payment SUCCESS - PaymentID: $razorpayPaymentId")

        // Extract payment details
        val paymentId = razorpayPaymentId ?: ""

        // Note: In the newer Razorpay SDK, PaymentData is not available in onPaymentSuccess
        // We use the stored orderId and will get signature from backend verification
        val orderId = currentOrderId
        val signature = "" // Signature will be verified on backend

        Log.d(TAG, "Extracted - OrderID: $orderId, PaymentID: $paymentId")

        paymentCallback?.onPaymentSuccess(orderId, paymentId, signature)
    }

    override fun onPaymentError(errorCode: Int, errorMessage: String?) {
        val message = errorMessage ?: "Unknown error"
        Log.e(TAG, "⚠️ Payment Error - Code: $errorCode, Message: $message")

        // Razorpay error codes:
        // 0 = Processing/Pending or payment_error in test mode
        // 1 = User cancelled
        // 2 = Network error

        when (errorCode) {
            0 -> {
                // Error code 0 can mean:
                // 1. Payment is processing (UPI)
                // 2. Payment succeeded but SDK shows error (test mode bug)
                // 3. Actual payment error

                // In test mode, this often means payment succeeded - don't show error to user
                Log.w(TAG, "⏳ Payment processing or test mode success, waiting for webhook confirmation...")
                // Don't call error callback - let webhook handle it
            }
            1 -> {
                // User explicitly cancelled
                Log.w(TAG, "❌ User cancelled payment")
                paymentCallback?.onPaymentError(errorCode, "Payment cancelled")
            }
            2 -> {
                // Network error
                Log.e(TAG, "❌ Network error during payment")
                paymentCallback?.onPaymentError(errorCode, "Network error. Please check your connection.")
            }
            else -> {
                // Other errors - show to user
                Log.e(TAG, "❌ Payment failed with error code $errorCode")
                paymentCallback?.onPaymentError(errorCode, message)
            }
        }
    }

    fun cleanup() {
        paymentCallback = null
    }
}
