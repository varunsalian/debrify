package com.debrify.app.tv

import android.view.View
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowDialog

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvStremioTvMediaStartCharacterizationTest : TvPhase18OriginalTest() {
    @Test fun replaceIdentity() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertEquals("stremio_tv:${channel.id}",item().id)
    }

    @Test fun replaceTitle() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertEquals("Release title",item().title)
    }

    @Test fun replaceUrl() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertEquals("https://tv.invalid/new.mp4",item().url)
    }

    @Test fun replaceIndex() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertEquals(0,item().index)
    }

    @Test fun replaceSeason() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertEquals(2,item().season)
    }

    @Test fun replaceEpisode() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertEquals(3,item().episode)
    }

    @Test fun replacePoster() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertEquals("channel poster",item().artwork)
    }

    @Test fun replaceRating() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertEquals(8.5,item().rating)
    }

    @Test fun replaceDescription() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertEquals("old description",item().description)
    }

    @Test fun replaceProvider() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertEquals("Previous provider",item().provider)
    }

    @Test fun replaceResume() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertEquals(0L,item().resumePositionMs)
    }

    @Test fun replaceDuration() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertEquals(0L,item().durationMs)
    }

    @Test fun replaceResumeId() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertNull(item().resumeId)
    }

    @Test fun replaceSize() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertNull(item().sizeBytes)
    }

    @Test fun replaceTimestamp() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertEquals(before,item().updatedAt)
    }

    @Test fun replaceSourceTitle() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertEquals("Release title",item().sourceTitle)
    }

    @Test fun replaceSingleItem() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertEquals(1,model().items.size)
    }

    @Test fun replaceShowType() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertEquals("series",model().contentType)
    }

    @Test fun replaceImdb() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertEquals("ttnew",model().imdbId)
    }

    @Test fun replaceNextMap() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertTrue(model().nextEpisodeMap.isEmpty())
    }

    @Test fun replacePrevMap() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertTrue(model().prevEpisodeMap.isEmpty())
    }

    @Test fun replaceGroups() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertNull(model().collectionGroups)
    }

    @Test fun replaceImdbCache() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertEquals(mapOf(0 to "ttnew"),model().perItemImdbIds)
    }

    @Test fun replaceShowCaption() {
        val old=p2Item("Old",season=1,episode=1,provider="Previous provider").copy(artwork="old poster",description="old description",rating=7.1,resumePositionMs=55,durationMs=88,resumeId="old",sizeBytes=123)
         payload(old,p2Item().copy(index=1),type="series",imdb="ttold"); model().nextEpisodeMap=mapOf(0 to 1); model().prevEpisodeMap=mapOf(1 to 0); model().collectionGroups=listOf(org.json.JSONObject()); model().perItemImdbIds[1]="ttold"; set("ottShowName","Old show")
         val channel=p2Guide().apply { nowPlayingPoster="channel poster"; nowPlayingRating=8.5 }
         val before=android.os.SystemClock.uptimeMillis(); val map=mapOf<String,Any?>("contentImdbId" to "ttnew","contentType" to "series","contentSeason" to 2,"contentEpisode" to 3)
         call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),channel,map,"Release title","https://tv.invalid/new.mp4")
        assertNull(field("ottShowName"))
    }

    @Test fun replaceAbsentMetadataUsesPreviousPosterRatingAndEmptyType() {
        payload(p2Item().copy(artwork="old",rating=7.2)); val c=p2Guide(); call("replacePayloadWithStremioTvItem",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType),c,emptyMap<String,Any>(),"Now","https://tv.invalid/a"); assertEquals("old",item().artwork); assertEquals(7.2,item().rating); assertEquals("",model().contentType); assertNull(item().season); assertNull(item().episode); assertNull(model().imdbId); assertEquals(mapOf<Int,String?>(0 to null),model().perItemImdbIds)
    }

    @Test fun sourcesIndexNegative() {
        val entries=listOf(mapOf("name" to "First"),"skip",mapOf("name" to "Last")); call("updateStremioSourcesFromPlaybackMap",arrayOf(mapType),mapOf("stremioSources" to entries,"stremioCurrentSourceIndex" to -1))
         assertEquals(listOf("First","Last"),sources().map { it.name }); assertEquals(listOf(0,2),sources().map { it.index }); assertEquals(0,field("currentStremioSourceIndex"))
    }

    @Test fun sourcesIndexHigh() {
        val entries=listOf(mapOf("name" to "First"),"skip",mapOf("name" to "Last")); call("updateStremioSourcesFromPlaybackMap",arrayOf(mapType),mapOf("stremioSources" to entries,"stremioCurrentSourceIndex" to 9))
         assertEquals(listOf("First","Last"),sources().map { it.name }); assertEquals(listOf(0,2),sources().map { it.index }); assertEquals(1,field("currentStremioSourceIndex"))
    }

    @Test fun sourcesIndexSelected() {
        val entries=listOf(mapOf("name" to "First"),"skip",mapOf("name" to "Last")); call("updateStremioSourcesFromPlaybackMap",arrayOf(mapType),mapOf("stremioSources" to entries,"stremioCurrentSourceIndex" to 1))
         assertEquals(listOf("First","Last"),sources().map { it.name }); assertEquals(listOf(0,2),sources().map { it.index }); assertEquals(1,field("currentStremioSourceIndex"))
    }

    @Test fun sourcesIndexDefault() {
        val entries=listOf(mapOf("name" to "First"),"skip",mapOf("name" to "Last")); call("updateStremioSourcesFromPlaybackMap",arrayOf(mapType),mapOf("stremioSources" to entries))
         assertEquals(listOf("First","Last"),sources().map { it.name }); assertEquals(listOf(0,2),sources().map { it.index }); assertEquals(0,field("currentStremioSourceIndex"))
    }

    @Test fun sourcesAbsentKeepsListAndSelection() {
        set("currentStremioSourceIndex",1); val old=sources().toList(); call("updateStremioSourcesFromPlaybackMap",arrayOf(mapType),mapOf("stremioCurrentSourceIndex" to 0)); assertEquals(old,sources()); assertEquals(1,field("currentStremioSourceIndex"))
    }

    @Test fun sourcesEmptyClearsAndClampsToZero() {
        set("currentStremioSourceIndex",1); call("updateStremioSourcesFromPlaybackMap",arrayOf(mapType),mapOf("stremioSources" to emptyList<Any>())); assertTrue(sources().isEmpty()); assertEquals(0,field("currentStremioSourceIndex"))
    }

    @Test fun trioBadgeClassicWithSources() {
        set("ottSkinInstalled",false); set("ottSourcesButton",androidx.appcompat.widget.AppCompatButton(activity).apply { visibility=View.INVISIBLE })
         set("stremioTvGuideVisible",true); val c=p2Guide(); call("playStremioTvPlaybackMap",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType,boolType),c,mapOf("stremioSources" to listOf(mapOf("name" to "Only"))),"https://tv.invalid/a.mp4","New",false)
         assertEquals(View.VISIBLE,badge().visibility); assertEquals(listOf("media:https://tv.invalid/a.mp4","prepare","playWhenReady:true","play"),probe.events)
    }

    @Test fun trioBadgeClassicEmpty() {
        set("ottSkinInstalled",false); set("ottSourcesButton",androidx.appcompat.widget.AppCompatButton(activity).apply { visibility=View.INVISIBLE })
         set("stremioTvGuideVisible",true); val c=p2Guide(); call("playStremioTvPlaybackMap",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType,boolType),c,mapOf("stremioSources" to emptyList<Any>()),"https://tv.invalid/a.mp4","New",false)
         assertEquals(View.GONE,badge().visibility); assertEquals(listOf("media:https://tv.invalid/a.mp4","prepare","playWhenReady:true","play"),probe.events)
    }

    @Test fun trioBadgeOttWithSources() {
        set("ottSkinInstalled",true); set("ottSourcesButton",androidx.appcompat.widget.AppCompatButton(activity).apply { visibility=View.INVISIBLE })
         set("stremioTvGuideVisible",true); val c=p2Guide(); call("playStremioTvPlaybackMap",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType,boolType),c,mapOf("stremioSources" to listOf(mapOf("name" to "Only"))),"https://tv.invalid/a.mp4","New",false)
         assertEquals(View.VISIBLE,(field("ottSourcesButton") as View).visibility); assertEquals(listOf("media:https://tv.invalid/a.mp4","prepare","playWhenReady:true","play"),probe.events)
    }

    @Test fun trioBadgeOttEmpty() {
        set("ottSkinInstalled",true); set("ottSourcesButton",androidx.appcompat.widget.AppCompatButton(activity).apply { visibility=View.INVISIBLE })
         set("stremioTvGuideVisible",true); val c=p2Guide(); call("playStremioTvPlaybackMap",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType,boolType),c,mapOf("stremioSources" to emptyList<Any>()),"https://tv.invalid/a.mp4","New",false)
         assertEquals(View.GONE,(field("ottSourcesButton") as View).visibility); assertEquals(listOf("media:https://tv.invalid/a.mp4","prepare","playWhenReady:true","play"),probe.events)
    }

    @Test fun trioResumeResetAndReadySeekSignal() {
        set("pendingSeekMs",999L); set("pendingItemTraktPercent",99.0); set("percentSeekApplied",true); set("hasEverBeenReady",true); set("resumeHoldTargetMs",999L); readiness().onReady()
         val c=p2Guide().apply { isSwitchingChannel=true }; call("playStremioTvPlaybackMap",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType,boolType),c,mapOf("startAtPercent" to 0.4),"https://tv.invalid/a.mp4","New",false)
         assertEquals(0.4,model().startAtPercent,0.0); assertFalse(field("percentSeekApplied") as Boolean); assertEquals(0L,field("pendingSeekMs")); assertEquals(0.0,field("pendingItemTraktPercent")); assertEquals(0L,field("resumeHoldTargetMs")); assertFalse(field("hasEverBeenReady") as Boolean); assertFalse(readiness().canSelect(true)); assertFalse(c.isSwitchingChannel); assertEquals("New",title())
    }

    @Test fun trioReadyWaitTrue() {
        set("stremioTvGuideVisible",true); val c=p2Guide(); call("playStremioTvPlaybackMap",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType,boolType),c,emptyMap<String,Any>(),"https://tv.invalid/a.mp4","New",true); assertEquals(true,field("guidePanelReadyListener") != null); assertEquals(1,probe.listeners.size)
    }

    @Test fun trioReadyWaitFalse() {
        set("stremioTvGuideVisible",true); val c=p2Guide(); call("playStremioTvPlaybackMap",arrayOf(StremioTvGuideChannel::class.java,mapType,stringType,stringType,boolType),c,emptyMap<String,Any>(),"https://tv.invalid/a.mp4","New",false); assertEquals(false,field("guidePanelReadyListener") != null); assertEquals(0,probe.listeners.size)
    }
}
