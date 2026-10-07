package com.debrify.app.tv

import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.View
import android.view.ViewGroup
import android.widget.ProgressBar
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.R

internal data class IptvEpgProgram(
    val title: String,
    val description: String?,
    val startMs: Long,
    val stopMs: Long,
    val hasArchive: Boolean,
)

internal class IptvEpgAdapter(
    private var programs: List<IptvEpgProgram>,
    private val onReplay: (IptvEpgProgram) -> Unit,
    private val onRecordFuture: (IptvEpgProgram) -> Unit,
    // Styled-look inputs; null tokens = classic. Invariant styling happens
    // once per holder in onCreateViewHolder.
    private val tokens: GuideTokens? = null,
    private val style: GuideStyle = GuideStyle.CLASSIC,
    private val monoTypeface: Typeface? = null,
    private val headlineTypeface: Typeface? = null,
    private val rowRadiusPx: Float = 0f,
    private val rowStrokePx: Int = 0,
) : RecyclerView.Adapter<IptvEpgAdapter.ViewHolder>() {

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val time: TextView = view.findViewById(R.id.iptv_epg_program_time)
        val title: TextView = view.findViewById(R.id.iptv_epg_program_title)
        val description: TextView = view.findViewById(R.id.iptv_epg_program_description)
        val progress: ProgressBar = view.findViewById(R.id.iptv_epg_program_progress)
        val now: TextView = view.findViewById(R.id.iptv_epg_program_now)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = android.view.LayoutInflater.from(parent.context)
            .inflate(R.layout.item_iptv_epg_program, parent, false)
        val holder = ViewHolder(view)
        val t = tokens ?: return holder
        view.background = t.rowBackground(rowRadiusPx, rowStrokePx)
        holder.time.setTextColor(t.fgDim)
        holder.title.setTextColor(t.fg)
        holder.description.setTextColor(t.fgFaint)
        holder.progress.progressTintList =
            android.content.res.ColorStateList.valueOf(t.accent)
        holder.progress.progressBackgroundTintList =
            android.content.res.ColorStateList.valueOf(t.hairline2)
        // NOW/REPLAY chip: an outlined token tag (the text flips per bind,
        // the chrome doesn't).
        holder.now.background = GradientDrawable().apply {
            cornerRadius = if (style == GuideStyle.CONSOLE) {
                view.resources.displayMetrics.density * 2f
            } else {
                view.resources.displayMetrics.density * 4f
            }
            setColor(Color.TRANSPARENT)
            setStroke(1, t.accent)
        }
        holder.now.setTextColor(t.accent)
        when (style) {
            GuideStyle.CONSOLE -> {
                holder.time.typeface = monoTypeface ?: holder.time.typeface
                holder.now.typeface = monoTypeface ?: holder.now.typeface
            }
            GuideStyle.EDITION -> {
                holder.title.typeface = headlineTypeface ?: holder.title.typeface
            }
            else -> {}
        }
        return holder
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val program = programs[position]
        val nowMs = System.currentTimeMillis()
        val airing = program.startMs <= nowMs && nowMs < program.stopMs
        val elapsed = nowMs - program.startMs
        val duration = (program.stopMs - program.startMs).coerceAtLeast(1L)
        val replayable = program.hasArchive && program.startMs <= nowMs

        holder.time.text = android.text.format.DateFormat
            .getTimeFormat(holder.itemView.context)
            .format(java.util.Date(program.startMs))
        holder.title.text = program.title
        holder.description.text = program.description
        holder.description.visibility =
            if (program.description.isNullOrBlank()) View.GONE else View.VISIBLE
        holder.now.text = if (airing && replayable) "START OVER" else if (airing) "NOW" else "REPLAY"
        holder.now.visibility = if (airing || replayable) View.VISIBLE else View.GONE
        // Styled only: the airing row wears the quiet selected tint (and a
        // recycled holder explicitly clears it). Classic never sets it.
        if (tokens != null) holder.itemView.isSelected = airing
        holder.progress.visibility = if (airing) View.VISIBLE else View.GONE
        holder.progress.progress =
            ((elapsed.coerceIn(0L, duration) * 1000L) / duration).toInt()
        holder.itemView.alpha =
            if (program.stopMs < nowMs && !replayable) 0.55f else 1f
        holder.itemView.setOnClickListener {
            when {
                replayable -> onReplay(program)
                // Future programme: OK offers to schedule a recording. The
                // activity gates (engine on, channel recordable) and confirms.
                program.startMs > System.currentTimeMillis() -> onRecordFuture(program)
            }
        }
    }

    override fun getItemCount(): Int = programs.size

    fun updatePrograms(items: List<IptvEpgProgram>) {
        programs = items
        notifyDataSetChanged()
    }
}
