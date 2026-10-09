package com.debrify.app.tv

import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.R
import java.util.Locale

internal class TvPlaylistFocusNavigator(
    private val activity: AppCompatActivity,
    private val host: TvPlaylistOverlayController.Host,
    private val playlist: TvPlaylistOverlayController,
) {

    // Focus navigation state - prevents focus recovery from interfering with active navigation
    internal var isNavigating = false
    internal var navigationTargetPosition = -1
    internal val focusRecoveryHandler = Handler(Looper.getMainLooper())
    internal var focusRecoveryRunnable: Runnable? = null

    fun setupPlaylistNavigation() {
        android.util.Log.d("PlaylistNav", "setupPlaylistNavigation: Setting up navigation")

        // Trap LEFT/RIGHT focus inside RecyclerView, but allow UP/DOWN for season tabs
        host.playlistView.setOnKeyListener { view, keyCode, event ->
            if (!playlist.playlistVisible) {
                android.util.Log.d("PlaylistNav", "Key event but playlist not visible: keyCode=$keyCode")
                return@setOnKeyListener false
            }

            if (event.action == KeyEvent.ACTION_DOWN) {
                when (keyCode) {
                    KeyEvent.KEYCODE_DPAD_RIGHT -> {
                        // Simple delegation - movePlaylistFocus handles all logic including boundaries
                        android.util.Log.d("PlaylistNav", "DPAD_RIGHT pressed")
                        movePlaylistFocus(1)
                        true  // Always consume to prevent focus escape
                    }
                    KeyEvent.KEYCODE_DPAD_LEFT -> {
                        // Simple delegation - movePlaylistFocus handles all logic including boundaries
                        android.util.Log.d("PlaylistNav", "DPAD_LEFT pressed")
                        movePlaylistFocus(-1)
                        true  // Always consume to prevent focus escape
                    }
                    KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN -> {
                        android.util.Log.d("PlaylistNav", "UP/DOWN pressed - allowing navigation to season tabs")
                        false  // Allow UP/DOWN to navigate to season tabs
                    }
                    else -> false
                }
            } else {
                false
            }
        }

        // Add global focus change listener for debugging
        host.playlistView.viewTreeObserver.addOnGlobalFocusChangeListener { oldFocus, newFocus ->
            if (playlist.playlistVisible) {
                val oldPos = if (oldFocus != null && oldFocus.parent == host.playlistView) {
                    host.playlistView.getChildAdapterPosition(oldFocus)
                } else {
                    -1
                }
                val newPos = if (newFocus != null && newFocus.parent == host.playlistView) {
                    host.playlistView.getChildAdapterPosition(newFocus)
                } else {
                    -1
                }
                android.util.Log.d("PlaylistNav", "Focus changed: oldPos=$oldPos -> newPos=$newPos, newFocus=$newFocus")
                // Note: Removed focus escape recovery - LEFT/RIGHT trapping prevents unintended escapes,
                // and we want to allow intentional UP/DOWN navigation to season tabs
            }
        }

        // Guide skin: vertical/grid skins re-map the DPAD axes (no-op on
        // CLASSIC and the horizontal skins).
        playlist.guideSkin.applyGuideKeyOverride()
    }

    /**
     * Find the next focusable position starting from a given position, moving in the specified direction.
     * Skips over non-focusable items like SeasonHeaders (for series playlists).
     * Works for both series and collection/movie playlists.
     *
     * @param startPosition The position to start searching from (inclusive)
     * @param direction 1 for forward, -1 for backward
     * @return The next focusable position, or RecyclerView.NO_POSITION if none found
     */
    fun findNextFocusablePosition(startPosition: Int, direction: Int): Int {
        // Handle series playlist (has SeasonHeaders to skip)
        val seriesAdapter = playlist.seriesPlaylistAdapter
        if (seriesAdapter != null) {
            val itemCount = seriesAdapter.itemCount
            var position = startPosition
            while (position in 0 until itemCount) {
                // Check if this position is an Episode (focusable), not a Header
                if (seriesAdapter.getItemViewType(position) == 1) { // VIEW_TYPE_EPISODE = 1
                    return position
                }
                position += direction
            }
            return RecyclerView.NO_POSITION
        }

        // Handle collection/movie playlist (all items are focusable - no headers)
        val movieAdapter = playlist.moviePlaylistAdapter
        if (movieAdapter != null) {
            val itemCount = movieAdapter.itemCount
            // All items in movie playlist are focusable, just check bounds
            if (startPosition in 0 until itemCount) {
                return startPosition
            }
            return RecyclerView.NO_POSITION
        }

        // No playlist adapter available
        return RecyclerView.NO_POSITION
    }

    /**
     * Ensure focus remains within the playlist when it should be visible.
     * Called when focus might be lost due to view recycling or other issues.
     */
    fun ensureFocusInPlaylist() {
        // Don't interfere during active navigation
        if (!playlist.playlistVisible || isNavigating) return

        // Check if any child of playlistView currently has focus
        val hasFocus = host.playlistView.hasFocus() || host.playlistView.focusedChild != null
        if (hasFocus) return

        android.util.Log.d("PlaylistNav", "ensureFocusInPlaylist: Focus lost, recovering...")

        val layoutManager = host.playlistView.layoutManager as? LinearLayoutManager ?: return
        val firstVisible = layoutManager.findFirstVisibleItemPosition()
        val lastVisible = layoutManager.findLastVisibleItemPosition()

        if (firstVisible == RecyclerView.NO_POSITION) return

        // If we have a recent navigation target in visible range, prefer that
        if (navigationTargetPosition in firstVisible..lastVisible) {
            val holder = host.playlistView.findViewHolderForAdapterPosition(navigationTargetPosition)
            if (holder?.itemView != null && holder.itemView.isFocusable) {
                android.util.Log.d("PlaylistNav", "ensureFocusInPlaylist: Focusing recent target at $navigationTargetPosition")
                holder.itemView.requestFocus()
                return
            }
        }

        // Find the middle item in the visible range (not the first)
        // This prevents always jumping back to the beginning
        val middlePosition = (firstVisible + lastVisible) / 2

        // Search outward from the middle
        for (offset in 0..(lastVisible - firstVisible)) {
            val positions = listOf(middlePosition + offset, middlePosition - offset)
            for (pos in positions) {
                if (pos in firstVisible..lastVisible) {
                    val nextFocusable = findNextFocusablePosition(pos, 1)
                    if (nextFocusable in firstVisible..lastVisible) {
                        val holder = host.playlistView.findViewHolderForAdapterPosition(nextFocusable)
                        if (holder != null && holder.itemView.isFocusable) {
                            android.util.Log.d("PlaylistNav", "ensureFocusInPlaylist: Recovering focus to position $nextFocusable (middle-out)")
                            holder.itemView.requestFocus()
                            return
                        }
                    }
                }
            }
        }
    }

    /**
     * Transfer focus to a specific position using ViewTreeObserver for reliable timing.
     * This ensures layout is complete before attempting to focus.
     */
    fun transferFocusToPosition(targetPosition: Int) {
        val layoutManager = host.playlistView.layoutManager as? LinearLayoutManager ?: run {
            isNavigating = false
            return
        }

        android.util.Log.d("PlaylistNav", "transferFocusToPosition: target=$targetPosition")

        // Keep navigation flag active and track target
        isNavigating = true
        navigationTargetPosition = targetPosition

        // Scroll to position with some offset for visual comfort
        layoutManager.scrollToPositionWithOffset(targetPosition, 100)

        // Use ViewTreeObserver for reliable timing instead of nested posts
        host.playlistView.viewTreeObserver.addOnGlobalLayoutListener(object : android.view.ViewTreeObserver.OnGlobalLayoutListener {
            override fun onGlobalLayout() {
                host.playlistView.viewTreeObserver.removeOnGlobalLayoutListener(this)

                val holder = host.playlistView.findViewHolderForAdapterPosition(targetPosition)
                if (holder?.itemView != null && holder.itemView.isFocusable) {
                    android.util.Log.d("PlaylistNav", "transferFocusToPosition: Focusing target at $targetPosition")
                    val focused = holder.itemView.requestFocus()
                    android.util.Log.d("PlaylistNav", "transferFocusToPosition: Focus result=$focused for position $targetPosition")

                    // Clear navigation flag after a short delay to let focus settle
                    host.playlistView.postDelayed({
                        isNavigating = false
                        navigationTargetPosition = -1
                    }, 50)

                    if (!focused) {
                        // Focus failed, try once more after a short delay
                        host.playlistView.postDelayed({
                            host.playlistView.findViewHolderForAdapterPosition(targetPosition)?.itemView?.requestFocus()
                            isNavigating = false
                            navigationTargetPosition = -1
                        }, 50)
                    }
                } else {
                    android.util.Log.d("PlaylistNav", "transferFocusToPosition: Holder not found or not focusable, using fallback")
                    // Clear navigation state before fallback
                    isNavigating = false
                    navigationTargetPosition = -1
                    ensureFocusInPlaylist()
                }
            }
        })
    }

    fun movePlaylistFocus(delta: Int) {
        android.util.Log.d("PlaylistNav", "movePlaylistFocus: delta=$delta")

        // Set navigation flag to prevent focus recovery from interfering
        isNavigating = true

        val adapter = host.playlistView.adapter ?: run {
            isNavigating = false
            navigationTargetPosition = -1
            return
        }
        val layoutManager = host.playlistView.layoutManager as? LinearLayoutManager ?: run {
            isNavigating = false
            navigationTargetPosition = -1
            return
        }

        // Use navigationTargetPosition if we're in the middle of rapid navigation
        // This prevents stutter like 3 → 4 → 4 → 5 when pressing keys quickly
        val currentPosition = if (navigationTargetPosition >= 0) {
            // We have an ongoing navigation, use target as current position
            navigationTargetPosition
        } else {
            // Normal case: get from focused child
            val focusedChild = host.playlistView.focusedChild
            if (focusedChild != null) {
                host.playlistView.getChildAdapterPosition(focusedChild)
            } else {
                layoutManager.findFirstVisibleItemPosition()
            }
        }

        android.util.Log.d("PlaylistNav", "movePlaylistFocus: currentPosition=$currentPosition, navTarget=$navigationTargetPosition")
        if (currentPosition == RecyclerView.NO_POSITION) {
            android.util.Log.d("PlaylistNav", "movePlaylistFocus: NO_POSITION, aborting")
            isNavigating = false
            navigationTargetPosition = -1
            return
        }

        // Boundary checks - stop at start/end
        val itemCount = adapter.itemCount
        if (delta > 0 && currentPosition >= itemCount - 1) {
            android.util.Log.d("PlaylistNav", "movePlaylistFocus: Already at end, ignoring")
            isNavigating = false
            navigationTargetPosition = -1
            return
        } else if (delta < 0 && currentPosition <= 0) {
            android.util.Log.d("PlaylistNav", "movePlaylistFocus: Already at start, ignoring")
            isNavigating = false
            navigationTargetPosition = -1
            return
        }

        // Find the next focusable position (skipping headers)
        val searchStart = currentPosition + delta
        val targetPosition = findNextFocusablePosition(searchStart, delta)

        android.util.Log.d("PlaylistNav", "movePlaylistFocus: searchStart=$searchStart, targetPosition=$targetPosition")

        if (targetPosition == RecyclerView.NO_POSITION || targetPosition == currentPosition) {
            android.util.Log.d("PlaylistNav", "movePlaylistFocus: No valid target found or same position")
            isNavigating = false
            navigationTargetPosition = -1
            return
        }

        // Track the target position for rapid navigation support
        navigationTargetPosition = targetPosition

        // Check if target is already visible and can be focused directly
        val targetHolder = host.playlistView.findViewHolderForAdapterPosition(targetPosition)
        if (targetHolder != null && targetHolder.itemView.parent != null && targetHolder.itemView.isFocusable) {
            // Item is visible and focusable, focus it directly
            android.util.Log.d("PlaylistNav", "movePlaylistFocus: Target visible, focusing directly")
            val focused = targetHolder.itemView.requestFocus()
            // Clear navigation flag after short delay to let focus settle
            // Keep navigationTargetPosition for rapid key presses, clear later
            host.playlistView.postDelayed({
                isNavigating = false
                navigationTargetPosition = -1
            }, 100)  // Increased to 100ms for better rapid press handling
            if (!focused) {
                // Direct focus failed, use transfer method
                transferFocusToPosition(targetPosition)
            }
        } else {
            // Item is not visible or not ready, use reliable transfer method
            android.util.Log.d("PlaylistNav", "movePlaylistFocus: Target not visible, using transferFocusToPosition")
            transferFocusToPosition(targetPosition)
        }
    }
}
