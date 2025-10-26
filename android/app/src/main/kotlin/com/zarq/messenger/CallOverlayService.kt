package com.zarq.messenger

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import android.view.*
import android.widget.ImageView
import android.widget.TextView
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodChannel
import com.bumptech.glide.Glide
import com.bumptech.glide.load.engine.DiskCacheStrategy
import com.bumptech.glide.request.RequestOptions

class CallOverlayService : Service() {

    companion object {
        private const val TAG = "CallOverlayService"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "call_overlay_channel"
        private const val OVERLAY_CHANNEL = "com.zarq/overlay"

        // Keep reference to current service instance for state updates
        private var currentInstance: CallOverlayService? = null

        fun stop(context: Context) {
            val intent = Intent(context, CallOverlayService::class.java)
            context.stopService(intent)
        }

        // 🔧 FIX: Update mute state from app
        fun updateMuteState(context: Context, isMuted: Boolean) {
            currentInstance?.updateMuteButton(isMuted)
        }
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var isOverlayShown = false
    private var isExpanded = false
    private var callerName: String = "Unknown"
    private var isVideo: Boolean = false
    private var avatarUrl: String? = null
    private var isMuted: Boolean = false

    // Auto-collapse timer
    private var autoCollapseHandler: android.os.Handler? = null
    private var autoCollapseRunnable: Runnable? = null
    private val AUTO_COLLAPSE_DELAY = 30000L // 30 seconds

    // Wake lock to keep microphone active when app is minimized
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "CallOverlayService created")
        currentInstance = this
        createNotificationChannel()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        autoCollapseHandler = android.os.Handler(android.os.Looper.getMainLooper())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Get caller info from intent
        callerName = intent?.getStringExtra("callerName") ?: "Unknown"
        isVideo = intent?.getBooleanExtra("isVideo", false) ?: false
        avatarUrl = intent?.getStringExtra("avatarUrl")
        isMuted = intent?.getBooleanExtra("isMuted", false) ?: false

        Log.d(TAG, "=== CallOverlayService started ===")
        Log.d(TAG, "Caller: $callerName")
        Log.d(TAG, "Is Video: $isVideo")
        Log.d(TAG, "Avatar URL: $avatarUrl")
        Log.d(TAG, "Is Muted: $isMuted")
        Log.d(TAG, "=================================")

        // 🔧 FIX: Acquire wake lock to keep microphone active when app is minimized
        // This prevents Android from suspending the audio system in the background
        acquireWakeLock()

        // Start as foreground service
        val notification = createNotification(callerName, isVideo)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10+ requires specifying service type
            // CRITICAL: Include MICROPHONE type for Android 14+ to access mic in background
            val serviceType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL or
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            } else {
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
            }
            startForeground(NOTIFICATION_ID, notification, serviceType)
            Log.d(TAG, "Foreground service started with types: phoneCall + microphone")
        } else {
            startForeground(NOTIFICATION_ID, notification)
            Log.d(TAG, "Foreground service started (legacy)")
        }

        // Show overlay if permission is granted
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (android.provider.Settings.canDrawOverlays(this)) {
                showOverlay()
                Log.d(TAG, "Overlay permission granted, showing overlay")
            } else {
                Log.e(TAG, "No permission to draw overlays")
            }
        } else {
            showOverlay()
        }

        return START_STICKY
    }

    override fun onTaskRemoved(intent: Intent?) {
        super.onTaskRemoved(intent)
        Log.d(TAG, "Task removed - keeping service alive")
        // Don't stop service when task is removed - keep overlay visible
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Call Overlay",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Ongoing call overlay notification"
                setSound(null, null)
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(callerName: String, isVideo: Boolean): Notification {
        val callType = if (isVideo) "Video call" else "Voice call"

        // Intent to return to app
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("$callType in progress")
            .setContentText("Tap to return to call with $callerName")
            .setSmallIcon(android.R.drawable.stat_sys_phone_call)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .build()
    }

    private fun showOverlay() {
        if (isOverlayShown) {
            Log.d(TAG, "Overlay already shown")
            return
        }

        try {
            // Start with collapsed view (circular avatar)
            showCollapsedOverlay()
            isOverlayShown = true
            Log.d(TAG, "Overlay shown successfully (collapsed)")

        } catch (e: Exception) {
            Log.e(TAG, "Error showing overlay: ${e.message}", e)
        }
    }

    private fun showCollapsedOverlay() {
        // Remove old view if exists
        try {
            if (overlayView != null) {
                windowManager?.removeView(overlayView)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error removing old view: ${e.message}")
        }

        val inflater = LayoutInflater.from(this)
        overlayView = inflater.inflate(R.layout.call_overlay_collapsed, null)

        // Setup collapsed view
        setupCollapsedView(overlayView!!)

        // Layout parameters for circular overlay
        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = 20
            y = 100
        }

        // Add new view to window
        windowManager?.addView(overlayView, params)
        isExpanded = false

        // Cancel auto-collapse timer when manually collapsed
        cancelAutoCollapseTimer()

        Log.d(TAG, "Collapsed overlay shown")
    }

    private fun showExpandedOverlay() {
        // Remove old view if exists
        try {
            if (overlayView != null) {
                windowManager?.removeView(overlayView)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error removing old view: ${e.message}")
        }

        val inflater = LayoutInflater.from(this)
        overlayView = inflater.inflate(R.layout.call_overlay_expanded, null)

        // Setup expanded view
        setupExpandedView(overlayView!!)

        // Layout parameters for expanded overlay
        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = 20
            y = 100
        }

        // Add new view to window
        windowManager?.addView(overlayView, params)
        isExpanded = true

        // Start auto-collapse timer (collapse after 30 seconds)
        startAutoCollapseTimer()

        Log.d(TAG, "Expanded overlay shown")
    }

    private fun setupCollapsedView(view: View) {
        // Load avatar
        val avatarImage = view.findViewById<ImageView>(R.id.avatar_image)
        loadAvatar(avatarImage)

        // Make draggable with click detection
        makeDraggableWithClick(view) {
            // On click - expand
            Log.d(TAG, "Collapsed view clicked - expanding")
            showExpandedOverlay()
        }
    }

    private fun setupExpandedView(view: View) {
        // Load avatar
        val avatarImage = view.findViewById<ImageView>(R.id.avatar_image)
        loadAvatar(avatarImage)

        // Set caller name
        val callerNameText = view.findViewById<TextView>(R.id.caller_name)
        callerNameText?.text = callerName

        // Make draggable (no click handler for expanded view)
        makeDraggableWithClick(view, null)

        // Collapse button
        val collapseBtn = view.findViewById<ImageView>(R.id.collapse_btn)
        collapseBtn?.setOnClickListener {
            Log.d(TAG, "Collapse button clicked")
            showCollapsedOverlay()
        }

        // Mute/Unmute button
        val muteBtn = view.findViewById<ImageView>(R.id.mute_btn)
        updateMuteButton(muteBtn)
        muteBtn?.setOnClickListener {
            Log.d(TAG, "Mute button clicked")
            toggleMute()
            updateMuteButton(muteBtn)
        }

        // Open app button
        val openAppBtn = view.findViewById<ImageView>(R.id.open_app_btn)
        openAppBtn?.setOnClickListener {
            Log.d(TAG, "Open app button clicked")
            returnToApp()
        }

        // End call button
        val endCallBtn = view.findViewById<ImageView>(R.id.end_call_btn)
        endCallBtn?.setOnClickListener {
            Log.d(TAG, "End call button clicked")
            endCall()
        }
    }

    private fun loadAvatar(imageView: ImageView?) {
        imageView ?: return

        if (!avatarUrl.isNullOrEmpty()) {
            // Load avatar from URL using Glide
            val requestOptions = RequestOptions()
                .circleCrop()
                .diskCacheStrategy(DiskCacheStrategy.ALL)
                .placeholder(android.R.drawable.ic_menu_call)
                .error(android.R.drawable.ic_menu_call)

            Glide.with(this)
                .load(avatarUrl)
                .apply(requestOptions)
                .into(imageView)

            Log.d(TAG, "Loading avatar from URL: $avatarUrl")
        } else {
            // No avatar URL, use default icon
            imageView.setImageResource(android.R.drawable.ic_menu_call)
            Log.d(TAG, "No avatar URL, using default icon")
        }
    }

    private fun updateMuteButton(muteBtn: ImageView?) {
        if (isMuted) {
            muteBtn?.setImageResource(android.R.drawable.ic_lock_silent_mode) // Muted icon
        } else {
            muteBtn?.setImageResource(android.R.drawable.ic_btn_speak_now) // Unmuted icon
        }
    }

    // 🔧 FIX: Update mute state from app (called via companion object)
    private fun updateMuteButton(newMuteState: Boolean) {
        isMuted = newMuteState
        Log.d(TAG, "Updating mute button from app: isMuted=$isMuted")

        // Find and update the mute button if overlay is visible
        overlayView?.findViewById<ImageView>(R.id.mute_btn)?.let { muteBtn ->
            updateMuteButton(muteBtn)
            Log.d(TAG, "Mute button updated in overlay")
        }
    }

    private fun toggleMute() {
        isMuted = !isMuted
        Log.d(TAG, "Mute toggled: $isMuted")

        // Notify Flutter to mute/unmute
        try {
            MainActivity.flutterEngineInstance?.dartExecutor?.binaryMessenger?.let { messenger ->
                val channel = MethodChannel(messenger, OVERLAY_CHANNEL)
                channel.invokeMethod("toggleMute", mapOf("isMuted" to isMuted))
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error toggling mute: ${e.message}")
        }
    }

    private fun endCall() {
        Log.d(TAG, "End call button clicked")

        // Invoke Flutter method via MainActivity's engine
        try {
            MainActivity.flutterEngineInstance?.dartExecutor?.binaryMessenger?.let { messenger ->
                val channel = MethodChannel(messenger, OVERLAY_CHANNEL)
                channel.invokeMethod("endCall", null, object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        Log.d(TAG, "End call invoked successfully")
                    }
                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        Log.e(TAG, "End call error: $errorCode - $errorMessage")
                    }
                    override fun notImplemented() {
                        Log.w(TAG, "End call not implemented")
                    }
                })
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error invoking end call: ${e.message}")
        }

        stopSelf()
    }

    private fun makeDraggableWithClick(view: View, onClick: (() -> Unit)?) {
        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var hasMoved = false

        view.setOnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    val params = v.layoutParams as WindowManager.LayoutParams
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    hasMoved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val params = v.layoutParams as WindowManager.LayoutParams
                    val deltaX = (initialTouchX - event.rawX).toInt()
                    val deltaY = (event.rawY - initialTouchY).toInt()

                    params.x = initialX + deltaX
                    params.y = initialY + deltaY
                    windowManager?.updateViewLayout(v, params)

                    // Detect if moved more than 10 pixels
                    if (Math.abs(deltaX) > 10 || Math.abs(deltaY) > 10) {
                        hasMoved = true
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    // If didn't move much, treat as click
                    if (!hasMoved && onClick != null) {
                        Log.d(TAG, "Click detected on overlay")
                        onClick.invoke()
                    } else if (hasMoved) {
                        Log.d(TAG, "Drag completed")
                    }
                    true
                }
                else -> false
            }
        }
    }

    private fun returnToApp() {
        val intent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        startActivity(intent)
    }

    fun hideOverlay() {
        if (isOverlayShown && overlayView != null) {
            try {
                windowManager?.removeView(overlayView)
                isOverlayShown = false
                Log.d(TAG, "Overlay hidden - stacktrace:", Exception("Hide overlay called from"))
            } catch (e: Exception) {
                Log.e(TAG, "Error hiding overlay: ${e.message}", e)
            }
        } else {
            Log.d(TAG, "hideOverlay called but overlay not shown or view null")
        }
    }

    private fun startAutoCollapseTimer() {
        // Cancel any existing timer
        cancelAutoCollapseTimer()

        // Create new timer
        autoCollapseRunnable = Runnable {
            Log.d(TAG, "Auto-collapse timer triggered - collapsing to bubble")
            if (isExpanded) {
                showCollapsedOverlay()
            }
        }

        // Schedule collapse after 30 seconds
        autoCollapseHandler?.postDelayed(autoCollapseRunnable!!, AUTO_COLLAPSE_DELAY)
        Log.d(TAG, "Auto-collapse timer started (30 seconds)")
    }

    private fun cancelAutoCollapseTimer() {
        autoCollapseRunnable?.let {
            autoCollapseHandler?.removeCallbacks(it)
            Log.d(TAG, "Auto-collapse timer cancelled")
        }
        autoCollapseRunnable = null
    }

    private fun acquireWakeLock() {
        try {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "Zarq::CallWakeLock"
            ).apply {
                setReferenceCounted(false)
                acquire(60 * 60 * 1000L) // 1 hour max (safety timeout)
            }
            Log.d(TAG, "🔋 Wake lock acquired - microphone will stay active in background")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error acquiring wake lock: ${e.message}")
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.let {
                if (it.isHeld) {
                    it.release()
                    Log.d(TAG, "🔋 Wake lock released")
                }
            }
            wakeLock = null
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error releasing wake lock: ${e.message}")
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "CallOverlayService onDestroy called!")
        currentInstance = null
        cancelAutoCollapseTimer()
        releaseWakeLock()
        hideOverlay()
        Log.d(TAG, "CallOverlayService destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
