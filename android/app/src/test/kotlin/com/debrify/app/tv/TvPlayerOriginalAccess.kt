package com.debrify.app.tv

import android.content.Context
import android.view.View
import androidx.recyclerview.widget.RecyclerView
import org.json.JSONObject
import java.lang.reflect.InvocationTargetException
import android.graphics.drawable.Drawable
import android.widget.ImageView
import com.bumptech.glide.request.RequestListener
import com.bumptech.glide.request.target.DrawableImageViewTarget

/** Only this helper knows the original private JVM names/constructor order.
 * Move commits retarget this helper; the behavioural assertions stay unchanged.
 */
internal object TvPlayerOriginalAccess {
    private val movedFunctions = mapOf(
        "adoptIptvEpg" to "IptvEntryRulesKt",
        "androidDecoderStatus" to "TvStartupDiagnosticsKt",
        "buildAudioTrackLabel" to "TvTrackLabelsKt",
        "buildManualSubtitleDisplayLabel" to "SubtitleSearchQueryKt",
        "buildNowPlayingText" to "StremioTvGuideDataKt",
        "buildProtectedMediaOrigins" to "TvStartupDiagnosticsKt",
        "buildSubtitleSearchInitialQuery" to "SubtitleSearchQueryKt",
        "buildSubtitleTrackLabel" to "TvTrackLabelsKt",
        "classifyIptvError" to "IptvLoadErrorPolicyKt",
        "currentIptvStartOverProgramme" to "IptvEntryRulesKt",
        "diagnosticProvider" to "TvStartupDiagnosticsKt",
        "formatIptvRemaining" to "IptvEntryRulesKt",
        "formatTime" to "TvPlayerFormattingKt",
        "getAcceleratedSeekStep" to "TvPlayerFormattingKt",
        "iptvChannelEntry" to "IptvPayloadParsingKt",
        "iptvQualityFromLabel" to "IptvEntryRulesKt",
        "isExternalSubtitleOption" to "TvTrackLabelsKt",
        "isIptvSeriesSentinel" to "IptvEntryRulesKt",
        "isLoadingSubtitleOption" to "TvTrackLabelsKt",
        "isPikPakPlaybackItem" to "TvStartupDiagnosticsKt",
        "isSearchSubtitleOption" to "TvTrackLabelsKt",
        "isSegmentedStreamUrl" to "IptvRecordingUrlRulesKt",
        "isSideRenderableSubtitle" to "TvTrackLabelsKt",
        "isStremioIptvUrl" to "IptvEntryRulesKt",
        "languageOfOverride" to "TvTrackLabelsKt",
        "mrow" to "UnifiedMenuRowsKt",
        "originKey" to "TvStartupDiagnosticsKt",
        "parseIptvChannels" to "IptvPayloadParsingKt",
        "parseIptvLists" to "IptvPayloadParsingKt",
        "parseIptvSources" to "IptvPayloadParsingKt",
        "parseSeasonEpisodeFromTitle" to "SubtitleSearchQueryKt",
        "parseStringList" to "IptvPayloadParsingKt",
        "parseSubtitleCatalogResults" to "SubtitleSearchQueryKt",
        "rebuildNavigationMaps" to "PlaylistNavigationMapsKt",
        "recordingTimestamp" to "IptvRecordingUrlRulesKt",
        "reportIptvStreamResult" to "TvPlayerFlutterRequestsKt",
        "requestIptvEpg" to "TvPlayerFlutterRequestsKt",
        "requestIptvStreamUrls" to "TvPlayerFlutterRequestsKt",
        "requestMovieMetadataFromFlutter" to "TvPlayerFlutterRequestsKt",
        "requestQuickPlayNextEpisode" to "TvPlayerFlutterRequestsKt",
        "requestStreamFromFlutter" to "TvPlayerFlutterRequestsKt",
        "resolveSeasonEpisodeForSubtitle" to "SubtitleSearchQueryKt",
        "sanitizeRecordingName" to "IptvRecordingUrlRulesKt",
        "spellNumber" to "TvPlayerFormattingKt",
        "startupLog" to "TvStartupDiagnosticsKt",
        "updateStremioTvGuideChannelData" to "StremioTvGuideDataKt",
        "xtreamTsTwin" to "IptvRecordingUrlRulesKt",
    )

    private val controllerOwners = mapOf(
        "beginManualSourceCandidate" to "startupGateController",
        "beginStartupFailoverIfEligible" to "startupGateController",
        "commitManualSourceCandidate" to "startupGateController",
        "commitStartupCandidate" to "startupGateController",
        "manualSourceCandidateUrl" to "startupGateController",
        "manualSourceCommitCheck" to "startupGateController",
        "manualSourceMediaReplaced" to "startupGateController",
        "manualSourceRestoreInProgress" to "startupGateController",
        "manualSourceSwitchIndex" to "startupGateController",
        "manualSourceSwitchSnapshot" to "startupGateController",
        "manualSourceSwitchTimeout" to "startupGateController",
        "pikPakGateReprepare" to "startupGateController",
        "schedulePikPakGateReprepare" to "startupGateController",
        "startupCommitCheck" to "startupGateController",
        "startupFailedReleases" to "startupGateController",
        "startupFailoverCursor" to "startupGateController",
        "startupFailoverDispatching" to "startupGateController",
        "startupFailoverGeneration" to "startupGateController",
        "startupFailoverTimeout" to "startupGateController",
        "startupFirstFrameAtElapsedMs" to "startupGateController",
        "startupHasRemainingSavedSources" to "startupGateController",
        "startupMaxAttempts" to "startupGateController",
        "startupPikPakTorrentAcquisitionAttempted" to "startupGateController",
        "startupRecoveryAvailable" to "startupGateController",
        "startupRecoveryCandidateIndices" to "startupGateController",
        "startupRecoveryConsumed" to "startupGateController",
        "startupRecoveryFetching" to "startupGateController",
        "startupResolverProvider" to "startupGateController",
        "startupSourcesExhausted" to "startupGateController",
        "startupTryNextOnFailure" to "startupGateController",
        "cancelSourceSwitchWait" to "sourceSwitchController",
        "dropStaleSourceSwitchFeedback" to "sourceSwitchController",
        "hideStremioSourceBadge" to "sourceSwitchController",
        "hideStremioSourceBadgeImmediately" to "sourceSwitchController",
        "onStremioSourceSelected" to "sourceSwitchController",
        "resolveSourceToPlaylistViaFlutter" to "sourceSwitchController",
        "resolveStremioSourceViaFlutter" to "sourceSwitchController",
        "setupStremioSources" to "sourceSwitchController",
        "showStremioSourceBadge" to "sourceSwitchController",
        "sourceSwitchReadyListener" to "sourceSwitchController",
        "sourceSwitchTimeoutRunnable" to "sourceSwitchController",
        "switchToSourcePlaylist" to "sourceSwitchController.applier",
        "switchToStremioSource" to "sourceSwitchController.applier",
        "updateStremioQualityBadge" to "sourceSwitchController",
        "watchSourceSwitchOutcome" to "sourceSwitchController",
        "cancelGuideWait" to "stremioTvGuideController",
        "filterStremioTvChannels" to "stremioTvGuideController",
        "guidePanelReadyListener" to "stremioTvGuideController",
        "guidePanelTimeoutRunnable" to "stremioTvGuideController",
        "hideGuideWhenReady" to "stremioTvGuideController",
        "hideStremioTvGuide" to "stremioTvGuideController",
        "initStremioTvGuide" to "stremioTvGuideController",
        "isFocusInStremioTvGuideList" to "stremioTvGuideController",
        "requestGuideDataForVisibleChannels" to "stremioTvGuideController",
        "requestStremioTvNext" to "stremioTvGuideController",
        "setupStremioTvGuide" to "stremioTvGuideController",
        "showStremioTvGuide" to "stremioTvGuideController",
        "stremioTvChannelAdapter" to "stremioTvGuideController",
        "stremioTvChannelSwitchInProgress" to "stremioTvGuideController",
        "stremioTvChannels" to "stremioTvGuideController",
        "stremioTvGuideCountText" to "stremioTvGuideController",
        "stremioTvGuideCurrentName" to "stremioTvGuideController",
        "stremioTvGuideCurrentTitle" to "stremioTvGuideController",
        "stremioTvGuideList" to "stremioTvGuideController",
        "stremioTvGuideNowLetter" to "stremioTvGuideController",
        "stremioTvGuideNowPlaying" to "stremioTvGuideController",
        "stremioTvGuideNowPoster" to "stremioTvGuideController",
        "stremioTvGuideOverlay" to "stremioTvGuideController",
        "stremioTvGuideSearch" to "stremioTvGuideController",
        "stremioTvGuideVisible" to "stremioTvGuideController",
        "stremioTvNextInProgress" to "stremioTvGuideController",
        "stremioTvSwitchToken" to "stremioTvGuideController",
        "switchToStremioTvChannel" to "stremioTvGuideController",
        "toggleStremioTvGuide" to "stremioTvGuideController",
        "updateStremioTvGuideHeader" to "stremioTvGuideController",
        "applyIptvZapBannerMode" to "iptvZapBannerController",
        "applyStyledZapBannerMode" to "iptvZapBannerController.styled",
        "buildStyledIptvZapBanner" to "iptvZapBannerController.styled",
        "ensureIptvZapBanner" to "iptvZapBannerController",
        "hideIptvZapBanner" to "iptvZapBannerController",
        "iptvDockLayoutListenerAttached" to "iptvZapBannerController",
        "iptvZapAccent" to "iptvZapBannerController",
        "iptvZapBanner" to "iptvZapBannerController",
        "iptvZapBannerBody" to "iptvZapBannerController",
        "iptvZapBannerDocked" to "iptvZapBannerController",
        "iptvZapBannerEntry" to "iptvZapBannerController",
        "iptvZapBannerHideToken" to "iptvZapBannerController",
        "iptvZapBannerHintChannel" to "iptvZapBannerController",
        "iptvZapBannerHintJump" to "iptvZapBannerController",
        "iptvZapBannerLayoutListenerAttached" to "iptvZapBannerController",
        "iptvZapBannerLetter" to "iptvZapBannerController",
        "iptvZapBannerLogo" to "iptvZapBannerController",
        "iptvZapBannerMeta" to "iptvZapBannerController",
        "iptvZapBannerName" to "iptvZapBannerController",
        "iptvZapBannerNext" to "iptvZapBannerController",
        "iptvZapBannerNow" to "iptvZapBannerController",
        "iptvZapBannerNumber" to "iptvZapBannerController",
        "iptvZapBannerProgress" to "iptvZapBannerController",
        "iptvZapBannerRail" to "iptvZapBannerController",
        "iptvZapBannerTickToken" to "iptvZapBannerController",
        "iptvZapBannerTimes" to "iptvZapBannerController",
        "iptvZapGlassCardWidth" to "iptvZapBannerController.styled",
        "iptvZapStyledCard" to "iptvZapBannerController.styled",
        "iptvZapStyledEnd" to "iptvZapBannerController.styled",
        "iptvZapStyledLive" to "iptvZapBannerController.styled",
        "iptvZapStyledMeterRow" to "iptvZapBannerController.styled",
        "iptvZapStyledRec" to "iptvZapBannerController.styled",
        "iptvZapStyledRule" to "iptvZapBannerController.styled",
        "iptvZapStyledScrim" to "iptvZapBannerController.styled",
        "isRecordingCurrentIptvChannel" to "iptvZapBannerController",
        "paintIptvZapBannerEpg" to "iptvZapBannerController",
        "paintIptvZapBannerIdentity" to "iptvZapBannerController",
        "paintIptvZapBannerPosition" to "iptvZapBannerController",
        "paintStyledZapBannerEpg" to "iptvZapBannerController.styled",
        "paintStyledZapBannerIdentity" to "iptvZapBannerController.styled",
        "refreshIptvZapBannerPosition" to "iptvZapBannerController",
        "scheduleIptvZapBannerTick" to "iptvZapBannerController",
        "showIptvZapBanner" to "iptvZapBannerController",
        "styledZapHint" to "iptvZapBannerController.styled",
        "styledZapText" to "iptvZapBannerController.styled",
        "zapHint" to "iptvZapBannerController",
        "zapText" to "iptvZapBannerController",
        "activeSkipSegment" to "skipSegmentController",
        "armSleepAtEndOfItem" to "sleepTimerController",
        "canRecordCurrentIptv" to "iptvRecordingActionsController",
        "cancelSleepTimer" to "sleepTimerController",
        "currentSkipSegmentRequest" to "skipSegmentController",
        "dismissUpNext" to "upNextController",
        "engineRecordableUrl" to "iptvRecordingActionsController",
        "engineTaskIdForCurrentChannel" to "iptvRecordingActionsController",
        "ensureSkipSegments" to "skipSegmentController",
        "finalizeIptvRecordingIfActive" to "iptvRecordingActionsController",
        "fireSleepTimer" to "sleepTimerController",
        "getActiveSkipSegment" to "skipSegmentController",
        "getLoadedSkipSegmentKey" to "skipSegmentController",
        "getLoadingSkipSegmentKey" to "skipSegmentController",
        "getNotificationPermissionRequestCode" to "iptvRecordingActionsController",
        "getRecordingEngineEnabled" to "iptvRecordingActionsController",
        "getRecordingRegistryListener" to "iptvRecordingActionsController",
        "getSkipFocusOfferedKey" to "skipSegmentController",
        "getSkipSegmentCache" to "skipSegmentController",
        "getSkipSegmentFetchGeneration" to "skipSegmentController",
        "getSkipSegmentFetchJob" to "skipSegmentController",
        "getSkipSegmentScope" to "skipSegmentController",
        "getSkipSegments" to "skipSegmentController",
        "getSleepTimerDeadlineElapsedMs" to "sleepTimerController",
        "getSleepTimerHandler" to "sleepTimerController",
        "getSleepTimerMinuteOptions" to "sleepTimerController",
        "getSleepTimerMode" to "sleepTimerController",
        "getSleepTimerRunnable" to "sleepTimerController",
        "getUpNextCard" to "upNextController",
        "getUpNextCountdown" to "upNextController",
        "getUpNextDismissedForIndex" to "upNextController",
        "getUpNextHandler" to "upNextController",
        "getUpNextPoster" to "upNextController",
        "getUpNextTargetIndex" to "upNextController",
        "getUpNextTicker" to "upNextController",
        "getUpNextTitle" to "upNextController",
        "getUpNextVisible" to "upNextController",
        "hideUpNextCard" to "upNextController",
        "isCurrentIptvSegmented" to "iptvRecordingActionsController",
        "isSchedulableStreamUrl" to "iptvRecordingActionsController",
        "loadedSkipSegmentKey" to "skipSegmentController",
        "loadingSkipSegmentKey" to "skipSegmentController",
        "maybeAskNotificationPermission" to "iptvRecordingActionsController",
        "maybeShowUpNext" to "upNextController",
        "notificationPermissionRequestCode" to "iptvRecordingActionsController",
        "presentSkipSegment" to "skipSegmentController",
        "promptScheduleRecording" to "iptvRecordingActionsController",
        "recordingEngineEnabled" to "iptvRecordingActionsController",
        "recordingRegistryListener" to "iptvRecordingActionsController",
        "recordingResourceFor" to "iptvRecordingActionsController",
        "resetSkipSegmentState" to "skipSegmentController",
        "showUpNextCard" to "upNextController",
        "skipActiveSegment" to "skipSegmentController",
        "skipFocusOfferedKey" to "skipSegmentController",
        "skipSegmentCache" to "skipSegmentController",
        "skipSegmentFetchGeneration" to "skipSegmentController",
        "skipSegmentFetchJob" to "skipSegmentController",
        "skipSegmentScope" to "skipSegmentController",
        "skipSegments" to "skipSegmentController",
        "sleepTimerDeadlineElapsedMs" to "sleepTimerController",
        "sleepTimerHandler" to "sleepTimerController",
        "sleepTimerMinuteOptions" to "sleepTimerController",
        "sleepTimerMinutesLeft" to "sleepTimerController",
        "sleepTimerMode" to "sleepTimerController",
        "sleepTimerRunnable" to "sleepTimerController",
        "sleepTimerValueLabel" to "sleepTimerController",
        "startSleepCountdown" to "sleepTimerController",
        "toggleEngineRecording" to "iptvRecordingActionsController",
        "toggleIptvRecording" to "iptvRecordingActionsController",
        "triggerUpNext" to "upNextController",
        "upNextCard" to "upNextController",
        "upNextCountdown" to "upNextController",
        "upNextDismissedForIndex" to "upNextController",
        "upNextHandler" to "upNextController",
        "upNextPoster" to "upNextController",
        "upNextTargetIndex" to "upNextController",
        "upNextTicker" to "upNextController",
        "upNextTitle" to "upNextController",
        "upNextVisible" to "upNextController",
        "updateRecordButtonState" to "iptvRecordingActionsController",
        "updateSkipSegmentState" to "skipSegmentController",
        "activeExternalSubtitleUrl" to "subtitleController",
        "applyAndPersistSubtitleSettings" to "subtitleController",
        "applySelectedSubtitleTrack" to "subtitleController",
        "applySubtitleSettings" to "subtitleController",
        "autoSyncAppliedOffsetMs" to "autoSyncController",
        "autoSyncCardHideRunnable" to "autoSyncController",
        "autoSyncLadderDone" to "autoSyncController",
        "autoSyncLadderIdx" to "autoSyncController",
        "autoSyncLadderSec" to "autoSyncController",
        "autoSyncLadderTick" to "autoSyncController",
        "autoSyncPill" to "autoSyncController",
        "autoSyncPillAnnounceDismissRunnable" to "autoSyncController",
        "autoSyncPillAnnounceShowing" to "autoSyncController",
        "autoSyncPillLabel" to "autoSyncController",
        "autoSyncPillResultShowing" to "autoSyncController",
        "autoSyncPillRing" to "autoSyncController",
        "autoSyncPillWindowActive" to "autoSyncController",
        "autoSyncResultLabel" to "autoSyncController",
        "autoSyncResultUrl" to "autoSyncController",
        "autoSyncRunning" to "autoSyncController",
        "autoSyncVerifyMisses" to "autoSyncController",
        "autoSyncVerifyTick" to "autoSyncController",
        "cancelAutoSyncLadder" to "autoSyncController",
        "cancelAutoSyncVerify" to "autoSyncController",
        "currentSubtitleIdentity" to "subtitleController",
        "currentSubtitleTrackIndex" to "subtitleController",
        "ensureAutoSyncPill" to "autoSyncController",
        "externalSubtitleActive" to "subtitleController",
        "externalSubtitleCues" to "subtitleController",
        "externalSubtitleLoadToken" to "subtitleController",
        "externalSubtitleTicker" to "subtitleController",
        "getActiveExternalSubtitleUrl" to "subtitleController",
        "getAutoSyncAppliedOffsetMs" to "autoSyncController",
        "getAutoSyncCardHideRunnable" to "autoSyncController",
        "getAutoSyncLadderDone" to "autoSyncController",
        "getAutoSyncLadderIdx" to "autoSyncController",
        "getAutoSyncLadderSec" to "autoSyncController",
        "getAutoSyncLadderTick" to "autoSyncController",
        "getAutoSyncPill" to "autoSyncController",
        "getAutoSyncPillAnnounceDismissRunnable" to "autoSyncController",
        "getAutoSyncPillAnnounceShowing" to "autoSyncController",
        "getAutoSyncPillLabel" to "autoSyncController",
        "getAutoSyncPillResultShowing" to "autoSyncController",
        "getAutoSyncPillRing" to "autoSyncController",
        "getAutoSyncPillWindowActive" to "autoSyncController",
        "getAutoSyncResultLabel" to "autoSyncController",
        "getAutoSyncResultUrl" to "autoSyncController",
        "getAutoSyncRunning" to "autoSyncController",
        "getAutoSyncVerifyMisses" to "autoSyncController",
        "getAutoSyncVerifyTick" to "autoSyncController",
        "getCurrentSubtitleTrackIndex" to "subtitleController",
        "getExternalSubtitleActive" to "subtitleController",
        "getExternalSubtitleCues" to "subtitleController",
        "getExternalSubtitleLoadToken" to "subtitleController",
        "getExternalSubtitleTicker" to "subtitleController",
        "getLastExternalCueText" to "subtitleController",
        "getSubtitlePanelCallbacks" to "subtitleController",
        "getSubtitleSeekHandler" to "subtitleController",
        "getSubtitleSeekRunnable" to "subtitleController",
        "getSubtitleSettingsVisible" to "subtitleController",
        "getSubtitleTracks" to "subtitleController",
        "hideAutoSyncCard" to "autoSyncController",
        "hideAutoSyncPillView" to "autoSyncController",
        "hideSubtitleSettingsPanel" to "subtitleController",
        "isAutoSyncPrefEnabled" to "autoSyncController",
        "lastExternalCueText" to "subtitleController",
        "loadStremioSubtitle" to "subtitleController",
        "maybeRunAutoSyncVerify" to "autoSyncController",
        "onExternalSubtitleLoaded" to "subtitleController",
        "openAutoSyncPillWindow" to "autoSyncController",
        "rebuildSubtitleTrackList" to "subtitleController",
        "refreshSubtitlePanelForLoading" to "subtitleController",
        "renderExternalSubtitleCue" to "subtitleController",
        "revealAutoSyncPill" to "autoSyncController",
        "runSubtitleAutoSync" to "autoSyncController",
        "scheduleAutoSyncVerify" to "autoSyncController",
        "showSubtitleSettingsPanel" to "subtitleController",
        "showSubtitleTrackDialog" to "subtitleController",
        "showSyncOverlay" to "subtitleController",
        "showSyncToast" to "autoSyncController",
        "startAutoSyncLadder" to "autoSyncController",
        "startExternalSubtitleTicker" to "subtitleController",
        "stopAutoSyncPillWindow" to "autoSyncController",
        "stopExternalSubtitleRendering" to "subtitleController",
        "subtitlePanelCallbacks" to "subtitleController",
        "subtitleSeekHandler" to "subtitleController",
        "subtitleSeekRunnable" to "subtitleController",
        "subtitleSettingsVisible" to "subtitleController",
        "subtitleTracks" to "subtitleController",
        "umAppearanceRows" to "subtitleController",
        "umEmbeddedTrackRows" to "subtitleController",
        "umSelectStremioSubtitleByUrl" to "subtitleController",
        "umSelectSubtitleRowIndex" to "subtitleController",
        "umTimingRows" to "subtitleController",
        "acknowledgeRecoveryCheckpoint" to "progressReporter",
        "armIptvStremioStallWatchdog" to "iptvChannelStartController",
        "beginIptvPlayback" to "iptvChannelStartController",
        "beginIptvPlaybackAfterWatchRegistration" to "iptvChannelStartController",
        "cancelIptvStremioStallWatchdog" to "iptvChannelStartController",
        "cancelPendingIptvCatchupRequest" to "iptvStartOverController",
        "clearIptvStremioSources" to "iptvChannelStartController",
        "deliverProgress" to "progressReporter",
        "iptvCatchupToken" to "iptvStartOverController",
        "iptvStremioCandidateIndex" to "iptvChannelStartController",
        "iptvStremioCandidates" to "iptvChannelStartController",
        "iptvStremioChannelKey" to "iptvChannelStartController",
        "iptvStremioStallRunnable" to "iptvChannelStartController",
        "iptvStremioToken" to "iptvChannelStartController",
        "iptvStremioWinnerReported" to "iptvChannelStartController",
        "iptvWatchRegistrationToken" to "iptvChannelStartController",
        "lastLiveChannelArmedUrl" to "iptvChannelStartController",
        "lastLiveChannelRunnable" to "iptvChannelStartController",
        "lastLiveChannelSettleMs" to "iptvChannelStartController",
        "lastProgressAckAt" to "progressReporter",
        "lastProgressBridgeAvailable" to "progressReporter",
        "lastProgressLogAt" to "progressReporter",
        "locallyCompletedItemKeys" to "progressReporter",
        "noteLiveChannelPlaying" to "iptvChannelStartController",
        "populateIptvStremioSources" to "iptvChannelStartController",
        "progressAckCount" to "progressReporter",
        "progressSentCount" to "progressReporter",
        "recoveryCompletedItemKeys" to "progressReporter",
        "recoverySequence" to "progressReporter",
        "reportIptvStremioWinnerIfNeeded" to "iptvChannelStartController",
        "requestIptvCatchup" to "iptvStartOverController",
        "sendIptvProgress" to "progressReporter",
        "sendPlaybackActivityState" to "progressReporter",
        "sendPlaybackMaintenanceState" to "progressReporter",
        "sendProgress" to "progressReporter",
        "showIptvStartOverTimeline" to "iptvStartOverController",
        "stageRecoveryCheckpoint" to "progressReporter",
        "switchToIptvStremioSource" to "iptvChannelStartController",
        "toggleIptvStartOver" to "iptvStartOverController",
        "tryNextIptvStremioCandidate" to "iptvChannelStartController",
        "updateIptvStartOverButton" to "iptvStartOverController",
        "updateIptvStartOverSeekButton" to "iptvStartOverController",
    )

    fun isStartupArm(frame: StackTraceElement): Boolean =
        frame.className == TvStartupGateController::class.java.name &&
            frame.methodName.substringBefore('$') == "armStartupCandidate"

    private fun memberOwner(owner: Any, name: String): Any {
        if (owner !is AndroidTvTorrentPlayerActivity) return owner
        val controller = controllerOwners[name.removeSuffix("\$delegate")] ?: return owner
        return controller.split('.').fold(owner as Any) { current, field ->
            current.javaClass.getDeclaredField(field).apply { isAccessible = true }.get(current)!!
        }
    }

    fun type(name: String): Class<*> = Class.forName(
        "com.debrify.app.tv." + when (name) {
            "AndroidTvTorrentPlayerActivity\$IptvStremioCandidate" -> "IptvStremioCandidate"
            "AndroidTvTorrentPlayerActivity\$SleepTimerMode" -> "SleepTimerMode"
            "AndroidTvTorrentPlayerActivity\$SkipSegmentRequest" -> "SkipSegmentRequest"
            else -> name
        },
    )

    fun construct(name: String, vararg arguments: Any?): Any {
        val constructor = type(name).declaredConstructors.single {
            !it.isSynthetic && it.parameterCount == arguments.size
        }
        constructor.isAccessible = true
        return unwrap { constructor.newInstance(*arguments) }
    }

    fun call(owner: Any, name: String, vararg arguments: Any?): Any? {
        val actualOwner = memberOwner(owner, name)
        val method = actualOwner.javaClass.declaredMethods.single {
            it.name == name && it.parameterCount == arguments.size && !it.isBridge
        }
        method.isAccessible = true
        return unwrap { method.invoke(actualOwner, *arguments) }
    }

    /** Exact JVM signatures keep same-arity overloads distinct. */
    fun callTyped(owner: Any, name: String, types: Array<Class<*>>, vararg arguments: Any?): Any? {
        val facade = if (owner is AndroidTvTorrentPlayerActivity) movedFunctions[name]?.let(::type) else null
        val actualOwner = memberOwner(owner, name)
        val method = (facade ?: actualOwner.javaClass).getDeclaredMethod(name, *types).apply { isAccessible = true }
        return unwrap { method.invoke(if (facade == null) actualOwner else null, *arguments) }
    }

    fun constructTyped(name: String, types: Array<Class<*>>, vararg arguments: Any?): Any {
        if (name == "AndroidTvTorrentPlayerActivity\$IptvLiveLoadErrorPolicy") {
            check(types.contentEquals(arrayOf(AndroidTvTorrentPlayerActivity::class.java)))
            return movedPolicy(arguments.single() as AndroidTvTorrentPlayerActivity)
        }
        val constructor = type(name).getDeclaredConstructor(*types).apply { isAccessible = true }
        return unwrap { constructor.newInstance(*arguments) }
    }

    /** Invoke Kotlin's real omitted-argument dispatcher, including its mask. */
    fun callDefault(owner: Any, name: String, types: Array<Class<*>>, mask: Int, vararg arguments: Any?): Any? {
        val facade = if (owner is AndroidTvTorrentPlayerActivity) movedFunctions[name]?.let(::type) else null
        val actualOwner = memberOwner(owner, name)
        val receiverTypes = if (facade == null) arrayOf(actualOwner.javaClass) else emptyArray()
        val receiver = if (facade == null) arrayOf(actualOwner) else emptyArray()
        val method = (facade ?: actualOwner.javaClass).getDeclaredMethod(
            name + "\$default", *receiverTypes, *types, Int::class.javaPrimitiveType, Any::class.java,
        ).apply { isAccessible = true }
        return unwrap { method.invoke(null, *receiver, *arguments, mask, null) }
    }

    /** Retarget the former inner constructor without snapshotting its activity. */
    @androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
    private fun movedPolicy(activity: AndroidTvTorrentPlayerActivity): Any {
        val invokingThreads = mutableListOf<Thread>()
        val liveNow = {
            invokingThreads.add(Thread.currentThread())
            val entries = field(activity, "iptvChannels") as List<*>
            val index = field(activity, "currentIptvIndex") as Int
            (entries.getOrNull(index) as IptvChannelEntry?)?.isLive == true
        }
        val policy = type("IptvLiveLoadErrorPolicy").getDeclaredConstructor(kotlin.jvm.functions.Function0::class.java)
            .apply { isAccessible = true }.newInstance(liveNow) as androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
        org.junit.Assert.assertTrue("supplier must not run at construction", invokingThreads.isEmpty())
        val probe = java.util.concurrent.FutureTask<Unit> {
            policy.getMinimumLoadableRetryCount(androidx.media3.common.C.DATA_TYPE_MEDIA)
            val spec = androidx.media3.datasource.DataSpec(android.net.Uri.parse("https://example.test/probe"))
            policy.getRetryDelayMsFor(androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy.LoadErrorInfo(
                androidx.media3.exoplayer.source.LoadEventInfo(1, spec, 0L),
                androidx.media3.exoplayer.source.MediaLoadData(androidx.media3.common.C.DATA_TYPE_MEDIA),
                java.io.IOException("probe"), 1,
            ))
        }
        val invokingThread = Thread(probe, "policy-supplier-test")
        invokingThread.start()
        probe.get(5, java.util.concurrent.TimeUnit.SECONDS)
        org.junit.Assert.assertEquals("both methods invoke the supplier", 2, invokingThreads.size)
        invokingThreads.forEach { org.junit.Assert.assertSame("supplier runs on the invoking thread", invokingThread, it) }
        return policy
    }

    private fun <T> unwrap(action: () -> T): T = try {
        action()
    } catch (error: InvocationTargetException) {
        throw error.targetException
    }

    fun get(owner: Any, name: String): Any? {
        val getter = if (name.startsWith("is")) name else "get" + name.replaceFirstChar { it.uppercase() }
        return call(owner, getter)
    }

    fun field(owner: Any, name: String): Any? {
        val actualOwner = memberOwner(owner, name)
        return actualOwner.javaClass.getDeclaredField(name).apply { isAccessible = true }.get(actualOwner)
    }

    fun glideTracks(manager: com.bumptech.glide.RequestManager, request: com.bumptech.glide.request.Request): Boolean {
        val tracker = com.bumptech.glide.RequestManager::class.java.getDeclaredField("requestTracker")
            .apply { isAccessible = true }.get(manager)!!
        return (field(tracker, "requests") as Set<*>).contains(request)
    }

    fun set(owner: Any, name: String, value: Any?) {
        val actualOwner = memberOwner(owner, name)
        actualOwner.javaClass.getDeclaredField(name).apply { isAccessible = true }.set(actualOwner, value)
    }

    fun source(value: Any, index: Int = 3): Any {
        val companion = type("StremioSource").getDeclaredField("Companion").apply { isAccessible = true }.get(null)!!
        return call(companion, if (value is JSONObject) "fromJson" else "fromMap", value, index)!!
    }

    @Suppress("UNCHECKED_CAST")
    private fun adapter(name: String, vararg arguments: Any?) =
        construct(name, *arguments) as RecyclerView.Adapter<RecyclerView.ViewHolder>

    fun guide(season: Int, episode: Int, title: String? = null, watched: Boolean = false): Any =
        construct("GuideEpisode", true, season, episode, title, null, null, 8.5, 30, 300_000L, 1_800_000L, 40.0, watched)

    fun playlist(
        items: List<PlaybackItem>, guide: List<Any> = emptyList(),
        fetch: ((Int, Int) -> Unit)? = null,
        skin: ((View, PlaybackItem, Int, Boolean) -> Unit)? = null,
        focus: ((PlaybackItem, Int) -> Unit)? = null,
        click: (Int) -> Unit = {},
    ) = adapter("PlaylistAdapter", items, guide, fetch,
        com.debrify.app.R.layout.item_android_tv_playlist_entry_horizontal, skin, focus, click)

    fun groups(vararg groups: Pair<String, List<Int>>): Any = construct("MovieGroups",
        groups.map { construct("CollectionGroup", it.first, it.second) })

    fun movies(
        items: List<PlaybackItem>, groups: Any,
        skin: ((View, PlaybackItem, Int, Boolean) -> Unit)? = null,
        focus: ((PlaybackItem, Int) -> Unit)? = null,
        click: (Int) -> Unit = {},
    ) = adapter("MoviePlaylistAdapter", items, groups,
        com.debrify.app.R.layout.item_android_tv_playlist_entry_horizontal, skin, focus, click)

    fun channel(
        index: Int = 0, name: String = "Cinema", live: Boolean = true,
        current: Boolean = false, favorite: Boolean = false, loaded: Boolean = false,
        loading: Boolean = false, stop: Long = 0L, epg: String? = null,
        source: String? = "source", number: Int? = 7, group: String? = "Movies",
    ): Any = construct("IptvChannelEntry", index, number, name, "https://example.test/$index", null, group,
        live, current, 0L, emptyMap<String, String>(), epg, 0L, stop, false, false,
        "Next", 0L, loaded, loading, if (live) "live" else "vod", -1,
        null, null, source, "Source", favorite, null, null, null, null, null)

    fun channels(
        entries: MutableList<Any>, click: (Any) -> Unit = {}, longClick: ((Any) -> Unit)? = null,
        epg: ((Any) -> Unit)? = null, style: GuideStyle = GuideStyle.CLASSIC,
    ) = adapter("IptvChannelAdapter", entries, click, longClick, epg, GuideTokens.of(style), style,
        null, null, null, null, 8f, 1)

    fun program(title: String, start: Long, stop: Long, archive: Boolean = false, description: String? = null) =
        construct("IptvEpgProgram", title, description, start, stop, archive)

    fun epg(
        programs: List<Any>, replay: (Any) -> Unit = {}, record: (Any) -> Unit = {},
        style: GuideStyle = GuideStyle.CLASSIC,
    ) = adapter("IptvEpgAdapter", programs, replay, record, GuideTokens.of(style), style, null, null, 8f, 1)

    fun tvChannel(
        id: String = "one", name: String = "Cinema", current: Boolean = false,
        title: String? = "Film", progress: Float = 0.25f, data: Boolean = true,
        loading: Boolean = false, switching: Boolean = false,
    ): Any = construct("StremioTvGuideChannel", id, name, 7, "movie", true, current,
        title, null, "2024", 8.5, System.currentTimeMillis() + 3_600_000L, progress,
        "Next Film", null, "2025", 7.0, data, loading, switching)

    fun tvGuide(channels: MutableList<Any>, click: (Any) -> Unit = {}) = adapter("StremioTvGuideAdapter", channels, click)

    fun categories(selected: String? = null, search: Int = 123, style: GuideStyle = GuideStyle.CLASSIC,
                   click: (String) -> Unit = {}) =
        adapter("IptvCategoryAdapter", selected, search, GuideTokens.of(style), 8f, click)

    fun list(id: String, name: String): Any = construct("IptvListEntry", id, name, false)

    fun lists(entries: List<Any>, membership: Set<String>, style: GuideStyle = GuideStyle.CLASSIC,
              toggle: (Any) -> Unit = {}) =
        adapter("IptvListPickerAdapter", entries, membership, GuideTokens.of(style), 8f, toggle)

    fun ring(outer: AndroidTvTorrentPlayerActivity, context: Context): View =
        construct("AutoSyncRingView", context) as View

    fun defaultPayload(): Any {
        val constructor = type("PlaybackPayload").declaredConstructors.single { it.isSynthetic }
        constructor.isAccessible = true
        return unwrap { constructor.newInstance(
            "Title", null, "single", mutableListOf<PlaybackItem>(), 0, null,
            null, null, null, null, null, null, 0.0, 0.0, false, 0, 0, null,
            ((1 shl 18) - 1) xor ((1 shl 6) - 1), null,
        ) }
    }

    fun episodeHolder(view: View): RecyclerView.ViewHolder =
        construct("PlaylistAdapter\$EpisodeViewHolder", view, { _: Int -> }, null, null) as RecyclerView.ViewHolder

    /** Exercise the original listener installed by a real bind without network
     * or decoder timing. This is a test-only seam into Glide's request object.
     */
    @Suppress("UNCHECKED_CAST")
    fun artworkListener(image: ImageView): RequestListener<Drawable> {
        val request = DrawableImageViewTarget(image).request!!
        val listeners = request.javaClass.getDeclaredField("requestListeners").apply {
            isAccessible = true
        }.get(request) as List<RequestListener<Drawable>>
        return listeners.single()
    }
}
