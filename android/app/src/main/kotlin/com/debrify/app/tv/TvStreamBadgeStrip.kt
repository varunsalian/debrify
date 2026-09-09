package com.debrify.app.tv

import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import com.bumptech.glide.Glide

/** Non-focusable bounded wrapping chips. Matching is performed by Flutter's
 * cancellable worker; the native UI receives only finished display records. */
class TvStreamBadgeStrip(context: Context, private val chipHeightDp: Int = 24) : ViewGroup(context) {
    private var shown: List<Map<*, *>>? = null
    private val positions = mutableListOf<Pair<Int, Int>>()
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()

    fun show(badges: List<Map<*, *>>) {
        if (shown == badges) return
        val previous = shown
        shown = badges
        // Selection only changes built-in text colours. Keep those views and
        // their measured bounds, just as we keep imported artwork on focus.
        if (previous != null && previous.size == badges.size && childCount == badges.size &&
            badges.indices.all { i ->
                getChildAt(i) is TextView && previous[i]["label"] == badges[i]["label"] &&
                    (badges[i]["imageUrl"] as? String).isNullOrBlank()
            }) {
            badges.forEachIndexed { i, badge -> styleChip(getChildAt(i), badge) }
            return
        }
        clearImages()
        removeAllViews()
        for (badge in badges) {
            val label = badge["label"] as? String ?: continue
            val image = badge["imageUrl"] as? String
            val foreground = (badge["textColor"] as? Number)?.toInt() ?: -1
            val chip: View = if (image.isNullOrBlank()) {
                TextView(context).apply {
                    text = label.uppercase()
                    textSize = if (chipHeightDp == 22) 11f else chipHeightDp * .55f
                    if (chipHeightDp != 22) setTypeface(typeface, android.graphics.Typeface.BOLD)
                    setTextColor(foreground)
                    setSingleLine(true)
                    ellipsize = android.text.TextUtils.TruncateAt.END
                    maxWidth = dp(180)
                    gravity = android.view.Gravity.CENTER
                    setPadding(dp(7), 0, dp(7), 0)
                    layoutParams = LayoutParams(LayoutParams.WRAP_CONTENT, dp(chipHeightDp))
                }
            } else {
                BadgeArtworkView(context).apply {
                    contentDescription = label
                    scaleType = ImageView.ScaleType.FIT_CENTER
                    setPadding(dp(5), dp(2), dp(5), dp(2))
                    maxWidth = dp(chipHeightDp * 7 + 10)
                    layoutParams = LayoutParams(LayoutParams.WRAP_CONTENT, dp(chipHeightDp))
                    // Decode at display density, retaining aspect ratio. The
                    // drawable's dimensions determine width after loading.
                    Glide.with(this).load(image).fitCenter().override(dp(chipHeightDp * 7), dp(chipHeightDp - 4))
                        .placeholder(BadgeLabelDrawable(label, foreground, dp(chipHeightDp) * .55f))
                        .error(BadgeLabelDrawable(label, foreground, dp(chipHeightDp) * .55f)).into(this)
                }
            }
            chip.isFocusable = false
            chip.isClickable = false
            styleChip(chip, badge)
            addView(chip)
        }
        requestLayout()
    }

    private fun styleChip(chip: View, badge: Map<*, *>) {
        if (chip is TextView) chip.setTextColor((badge["textColor"] as? Number)?.toInt() ?: -1)
        val background = chip.background as? GradientDrawable ?: GradientDrawable().also {
            it.cornerRadius = dp(chipHeightDp).toFloat() * .23f
            chip.background = it
        }
        background.setColor((badge["fillColor"] as? Number)?.toInt() ?: 0xFF2A2A2A.toInt())
        val border = (badge["borderColor"] as? Number)?.toInt()
        background.setStroke(if (border == null) 0 else dp(1), border ?: 0)
    }

    private fun clearImages() {
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            if (child is ImageView) Glide.with(context.applicationContext).clear(child)
        }
    }

    override fun onDetachedFromWindow() {
        clearImages()
        super.onDetachedFromWindow()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val gap = dp(6)
        var x = 0
        var y = if (childCount > 0) dp(8) else 0
        var rowHeight = 0
        positions.clear()
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            val available = if (child.layoutParams.width > 0) minOf(width, child.layoutParams.width) else width
            child.measure(MeasureSpec.makeMeasureSpec(available,
                if (child.layoutParams.width > 0) MeasureSpec.EXACTLY else MeasureSpec.AT_MOST),
                MeasureSpec.makeMeasureSpec(dp(chipHeightDp), MeasureSpec.EXACTLY))
            if (x > 0 && x + child.measuredWidth > width) {
                x = 0; y += rowHeight + gap; rowHeight = 0
            }
            positions.add(x to y)
            x += child.measuredWidth + gap
            rowHeight = maxOf(rowHeight, child.measuredHeight)
        }
        setMeasuredDimension(width, resolveSize(y + rowHeight, heightMeasureSpec))
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
        for (i in 0 until childCount) {
            val child = getChildAt(i)
            val (x, y) = positions.getOrElse(i) { 0 to 0 }
            child.layout(x, y, x + child.measuredWidth, y + child.measuredHeight)
        }
    }
}

private class BadgeArtworkView(context: Context) : ImageView(context) {
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val height = MeasureSpec.getSize(heightMeasureSpec)
        val horizontalPadding = paddingLeft + paddingRight
        val available = when (MeasureSpec.getMode(widthMeasureSpec)) {
            MeasureSpec.UNSPECIFIED -> maxWidth
            else -> minOf(maxWidth, MeasureSpec.getSize(widthMeasureSpec))
        }
        val contentWidth = badgeArtworkWidth(
            drawable?.intrinsicWidth ?: 0, drawable?.intrinsicHeight ?: 0,
            (height - paddingTop - paddingBottom).coerceAtLeast(0),
            (available - horizontalPadding).coerceAtLeast(0),
        )
        setMeasuredDimension(resolveSize(contentWidth + horizontalPadding, widthMeasureSpec), height)
    }
}

private class BadgeLabelDrawable(private val label: String, foreground: Int, textSizePx: Float) : android.graphics.drawable.Drawable() {
    private val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
        color = foreground
        textSize = textSizePx
        typeface = android.graphics.Typeface.DEFAULT_BOLD
        textAlign = android.graphics.Paint.Align.CENTER
    }
    override fun getIntrinsicWidth() = kotlin.math.ceil(paint.measureText(label).toDouble()).toInt().coerceAtLeast(1)
    override fun getIntrinsicHeight() = kotlin.math.ceil((paint.descent() - paint.ascent()).toDouble()).toInt().coerceAtLeast(1)
    override fun draw(canvas: android.graphics.Canvas) {
        val text = android.text.TextUtils.ellipsize(label, android.text.TextPaint(paint), bounds.width().toFloat(), android.text.TextUtils.TruncateAt.END).toString()
        canvas.drawText(text, bounds.exactCenterX(), bounds.exactCenterY() - (paint.ascent() + paint.descent()) / 2, paint)
    }
    override fun setAlpha(alpha: Int) { paint.alpha = alpha }
    override fun setColorFilter(filter: android.graphics.ColorFilter?) { paint.colorFilter = filter }
    @Deprecated("Deprecated in Java")
    override fun getOpacity() = android.graphics.PixelFormat.TRANSLUCENT
}
