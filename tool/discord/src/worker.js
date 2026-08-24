/**
 * Debrify Discord bot — Cloudflare Worker (HTTP interactions endpoint).
 *
 * Flow:
 *   /bug  <platform>  → modal form → creates a labelled GitHub issue in the tracker
 *                        repo + posts a summary embed back into the channel.
 *   /feature <category> → same, for feature requests.
 *
 * Secrets (wrangler secret put / .dev.vars): DISCORD_TOKEN, DISCORD_PUBLIC_KEY, GITHUB_TOKEN
 * Vars (wrangler.toml):                      APP_ID, TRACKER_REPO
 */

const T = { PING: 1, COMMAND: 2, MODAL_SUBMIT: 5 };
const R = { PONG: 1, MESSAGE: 4, DEFERRED: 5, MODAL: 9 };
const C = { ROW: 1, TEXT: 4 };
const STYLE = { SHORT: 1, PARAGRAPH: 2 };
const EPHEMERAL = 64;

const PLATFORM_LABEL = {
  android: 'platform:android',
  'android-tv': 'platform:android-tv',
  windows: 'platform:windows',
  macos: 'platform:macos',
  linux: 'platform:linux',
  ios: 'platform:ios',
};
const CATEGORY_NAME = {
  playback: 'Playback', sources: 'Sources & Addons', iptv: 'IPTV',
  ui: 'UI / UX', integrations: 'Integrations', other: 'Other',
};

export default {
  async fetch(request, env, ctx) {
    if (request.method !== 'POST') {
      return new Response('Debrify Discord bot is running.', { status: 200 });
    }
    const body = await request.text();
    if (!(await verify(request, body, env.DISCORD_PUBLIC_KEY))) {
      return new Response('invalid request signature', { status: 401 });
    }
    const i = JSON.parse(body);

    if (i.type === T.PING) return json({ type: R.PONG });

    if (i.type === T.COMMAND) {
      const name = i.data.name;
      if (name === 'bug') return json(bugModal(opt(i, 'platform') || 'other'));
      if (name === 'feature') return json(featureModal(opt(i, 'category') || 'other'));
      return json(ephemeral('Unknown command.'));
    }

    if (i.type === T.MODAL_SUBMIT) {
      // Ack now (public deferred), do the slow work (GitHub + embed edit) after responding.
      ctx.waitUntil(handleSubmit(i, env));
      return json({ type: R.DEFERRED });
    }

    return json(ephemeral('Unsupported interaction.'));
  },
};

// ---------- modal builders ----------

function textRow(id, label, style, required, placeholder, max) {
  return {
    type: C.ROW,
    components: [{ type: C.TEXT, custom_id: id, label, style, required, placeholder, max_length: max }],
  };
}

function bugModal(platform) {
  return {
    type: R.MODAL,
    data: {
      custom_id: `bug:${platform}`,
      title: `Report a bug (${platform})`.slice(0, 45),
      components: [
        textRow('version', 'App version (e.g. 0.6.3-alpha)', STYLE.SHORT, true, 'Settings → About', 40),
        textRow('what', 'What happened?', STYLE.PARAGRAPH, true, 'Describe the bug', 1000),
        textRow('steps', 'Steps to reproduce', STYLE.PARAGRAPH, true, '1. …\n2. …\n3. …', 1000),
        textRow('expected', 'What did you expect? (optional)', STYLE.PARAGRAPH, false, '', 600),
        textRow('extra', 'Anything else? logs, addons (optional)', STYLE.PARAGRAPH, false, '', 1000),
      ],
    },
  };
}

function featureModal(category) {
  return {
    type: R.MODAL,
    data: {
      custom_id: `feature:${category}`,
      title: 'Feature request',
      components: [
        textRow('what', 'What would you like?', STYLE.PARAGRAPH, true, 'The feature you want', 1000),
        textRow('why', 'Why? what problem does it solve?', STYLE.PARAGRAPH, true, 'Your use case', 1000),
        textRow('elsewhere', 'Seen it in another app? (optional)', STYLE.SHORT, false, 'e.g. Stremio, Televizo', 100),
      ],
    },
  };
}

// ---------- modal submit → GitHub issue + embed ----------

async function handleSubmit(i, env) {
  const [kind, meta] = i.data.custom_id.split(':');
  const f = fields(i);
  const user = (i.member && i.member.user) || i.user || {};
  const reporter = user.username || 'unknown';
  const reporterId = user.id || '';

  let title, labels, issueBody, embed;
  if (kind === 'bug') {
    title = `[bug] ${clip(f.what, 80)}`;
    labels = ['bug', PLATFORM_LABEL[meta], 'status:needs-info'].filter(Boolean);
    issueBody = bugBody(f, meta, reporter, reporterId);
    embed = {
      title: '🐞 Bug report received',
      description: reporterId ? `From <@${reporterId}> — thanks, logged for the team.` : 'Logged for the team.',
      color: 0xd73a4a,
      fields: [
        { name: 'Platform', value: meta, inline: true },
        { name: 'Version', value: f.version || '—', inline: true },
        { name: 'What happened', value: clip(f.what, 1024) },
      ],
    };
  } else {
    title = `[feature] ${clip(f.what, 80)}`;
    labels = ['feature', 'status:needs-info'];
    issueBody = featureBody(f, meta, reporter, reporterId);
    embed = {
      title: '✨ Feature request received',
      description: reporterId ? `From <@${reporterId}> — thanks!` : 'Thanks!',
      color: 0xa2eeef,
      fields: [
        { name: 'Category', value: CATEGORY_NAME[meta] || meta, inline: true },
        { name: 'Request', value: clip(f.what, 1024) },
      ],
    };
  }

  const issue = await createIssue(env, title, issueBody, labels);
  if (issue) embed.footer = { text: `Tracked internally as #${issue}` };

  await editOriginal(env, i.token, { embeds: [embed] });
}

async function createIssue(env, title, body, labels) {
  try {
    const res = await fetch(`https://api.github.com/repos/${env.TRACKER_REPO}/issues`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${env.GITHUB_TOKEN}`,
        Accept: 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'debrify-discord-bot',
      },
      body: JSON.stringify({ title, body, labels }),
    });
    if (res.ok) return (await res.json()).number;
    console.log('GitHub issue create failed', res.status, await res.text());
  } catch (e) {
    console.log('GitHub issue create error', e);
  }
  return null;
}

function editOriginal(env, token, payload) {
  return fetch(`https://discord.com/api/v10/webhooks/${env.APP_ID}/${token}/messages/@original`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
}

// ---------- issue body ----------

function bugBody(f, platform, reporter, reporterId) {
  return [
    `**Reporter:** ${reporter}${reporterId ? ` (Discord ID: ${reporterId})` : ''}`,
    `**Platform:** ${platform}`,
    `**App version:** ${f.version || '—'}`,
    '',
    '### What happened',
    f.what || '—',
    '',
    '### Steps to reproduce',
    f.steps || '—',
    '',
    '### Expected result',
    f.expected || '—',
    ...(f.extra ? ['', '### Anything else', f.extra] : []),
    '',
    '---',
    '_Filed via the `/bug` form._',
  ].join('\n');
}

function featureBody(f, category, reporter, reporterId) {
  return [
    `**Reporter:** ${reporter}${reporterId ? ` (Discord ID: ${reporterId})` : ''}`,
    `**Category:** ${CATEGORY_NAME[category] || category}`,
    '',
    '### What they want',
    f.what || '—',
    '',
    '### Why / use case',
    f.why || '—',
    ...(f.elsewhere ? ['', '### Seen elsewhere', f.elsewhere] : []),
    '',
    '---',
    '_Filed via the `/feature` form._',
  ].join('\n');
}

// ---------- helpers ----------

function opt(i, name) {
  const o = (i.data.options || []).find((x) => x.name === name);
  return o ? o.value : null;
}

function fields(i) {
  const out = {};
  for (const row of i.data.components || []) {
    const c = row.components[0];
    out[c.custom_id] = (c.value || '').trim();
  }
  return out;
}

function clip(s, n) {
  s = (s || '').trim() || '—';
  return s.length > n ? s.slice(0, n - 1) + '…' : s;
}

function json(obj) {
  return new Response(JSON.stringify(obj), { headers: { 'Content-Type': 'application/json' } });
}

function ephemeral(content) {
  return { type: R.MESSAGE, data: { content, flags: EPHEMERAL } };
}

// Ed25519 signature verification (Cloudflare Workers WebCrypto).
async function verify(request, body, publicKeyHex) {
  const sig = request.headers.get('x-signature-ed25519');
  const ts = request.headers.get('x-signature-timestamp');
  if (!sig || !ts || !publicKeyHex) return false;
  try {
    const key = await crypto.subtle.importKey('raw', hex(publicKeyHex), { name: 'Ed25519' }, false, ['verify']);
    const data = new TextEncoder().encode(ts + body);
    return await crypto.subtle.verify('Ed25519', key, hex(sig), data);
  } catch (e) {
    console.log('verify error', e);
    return false;
  }
}

function hex(s) {
  const out = new Uint8Array(s.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(s.substr(i * 2, 2), 16);
  return out;
}
