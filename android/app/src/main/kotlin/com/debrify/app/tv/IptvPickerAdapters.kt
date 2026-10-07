package com.debrify.app.tv

import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.R

internal class IptvCategoryAdapter(
    private val selectedCategory: String?,
    private val searchViewId: Int,
    private val tokens: GuideTokens? = null,
    private val rowRadiusPx: Float = 0f,
    private val onSelected: (String) -> Unit,
) : RecyclerView.Adapter<IptvCategoryAdapter.ViewHolder>() {
    private val categories = mutableListOf<String>()

    class ViewHolder(val label: TextView) : RecyclerView.ViewHolder(label)

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val density = parent.resources.displayMetrics.density
        fun px(dp: Int) = (dp * density).toInt()
        val label = TextView(parent.context).apply {
            layoutParams = RecyclerView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                px(52),
            ).apply {
                bottomMargin = px(6)
            }
            isFocusable = true
            isClickable = true
            gravity = Gravity.CENTER_VERTICAL
            setPadding(px(16), 0, px(16), 0)
            if (tokens == null) {
                setBackgroundResource(R.drawable.iptv_premium_button_bg)
                setTextColor(
                    ContextCompat.getColorStateList(
                        context,
                        R.color.iptv_premium_button_text,
                    ),
                )
            } else {
                background = tokens.buttonBackground(rowRadiusPx)
                setTextColor(tokens.buttonTextColors())
            }
            textSize = 15f
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            stateListAnimator = null
        }

        return ViewHolder(label)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val category = categories[position]
        holder.label.text = category
        holder.label.isSelected =
            category == (selectedCategory ?: "All categories")
        holder.label.nextFocusUpId =
            if (position == 0) searchViewId else View.NO_ID
        holder.label.setOnClickListener { onSelected(category) }
        holder.label.setOnFocusChangeListener { view, focused ->
            view.animate()
                .scaleX(if (focused) 1.015f else 1f)
                .scaleY(if (focused) 1.015f else 1f)
                .setDuration(120)
                .start()
        }
    }

    override fun getItemCount(): Int = categories.size

    fun update(items: List<String>) {
        categories.clear()
        categories.addAll(items)
        notifyDataSetChanged()
    }
}

internal class IptvListPickerAdapter(
    private val lists: List<IptvListEntry>,
    private val membership: Set<String>,
    private val tokens: GuideTokens? = null,
    private val rowRadiusPx: Float = 0f,
    private val onToggle: (IptvListEntry) -> Unit,
) : RecyclerView.Adapter<IptvListPickerAdapter.ViewHolder>() {
    // No rows until the channel's real membership has landed — see the
    // success callback in showIptvListPicker.
    private var ready = false

    fun setReady(value: Boolean) {
        if (ready == value) return
        ready = value
        notifyDataSetChanged()
    }

    class ViewHolder(val label: TextView) : RecyclerView.ViewHolder(label)

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val density = parent.resources.displayMetrics.density
        fun px(dp: Int) = (dp * density).toInt()
        val label = TextView(parent.context).apply {
            layoutParams = RecyclerView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                px(52),
            ).apply {
                bottomMargin = px(6)
            }
            isFocusable = true
            isClickable = true
            gravity = Gravity.CENTER_VERTICAL
            setPadding(px(16), 0, px(16), 0)
            if (tokens == null) {
                setBackgroundResource(R.drawable.iptv_premium_button_bg)
                setTextColor(
                    ContextCompat.getColorStateList(
                        context,
                        R.color.iptv_premium_button_text,
                    ),
                )
            } else {
                background = tokens.buttonBackground(rowRadiusPx)
                setTextColor(tokens.buttonTextColors())
            }
            textSize = 15f
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
            stateListAnimator = null
        }
        return ViewHolder(label)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val list = lists[position]
        val checked = membership.contains(list.id)
        holder.label.text = if (checked) "\u2713  ${list.name}" else list.name
        holder.label.isSelected = checked
        holder.label.setOnClickListener {
            onToggle(list)
            notifyItemChanged(position)
        }
        holder.label.setOnFocusChangeListener { view, focused ->
            view.animate()
                .scaleX(if (focused) 1.015f else 1f)
                .scaleY(if (focused) 1.015f else 1f)
                .setDuration(120)
                .start()
        }
    }

    override fun getItemCount(): Int = if (ready) lists.size else 0
}
