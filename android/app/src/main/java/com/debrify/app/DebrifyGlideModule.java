package com.debrify.app;

import android.content.Context;
import com.bumptech.glide.GlideBuilder;
import com.bumptech.glide.annotation.GlideModule;
import com.bumptech.glide.load.engine.cache.InternalCacheDiskCacheFactory;
import com.bumptech.glide.module.AppGlideModule;

/** Native TV artwork shares a bounded disk cache across player surfaces. */
@GlideModule
public final class DebrifyGlideModule extends AppGlideModule {
    @Override
    public void applyOptions(Context context, GlideBuilder builder) {
        // Keep the existing directory so Glide trims previously cached artwork.
        builder.setDiskCache(new InternalCacheDiskCacheFactory(context, 64L * 1024 * 1024));
    }
}
