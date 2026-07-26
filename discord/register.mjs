/**
 * Register the /bug and /feature slash commands to the Debrify guild (instant).
 * Run: node register.mjs   (or: npm run register)
 * Needs DISCORD_TOKEN from env or ./.dev.vars.
 */
import { readFileSync } from 'node:fs';

const cfg = JSON.parse(readFileSync(new URL('./config.json', import.meta.url)));

function devVars() {
  const v = {};
  try {
    for (const line of readFileSync(new URL('./.dev.vars', import.meta.url), 'utf8').split('\n')) {
      const m = line.match(/^\s*([A-Z_]+)\s*=\s*(.*)$/);
      if (m) v[m[1]] = m[2].trim();
    }
  } catch {}
  return v;
}

const TOKEN = process.env.DISCORD_TOKEN || devVars().DISCORD_TOKEN;
if (!TOKEN) {
  console.error('✘ No DISCORD_TOKEN (set env var or discord/.dev.vars).');
  process.exit(1);
}

const choices = (pairs) => pairs.map(([name, value]) => ({ name, value }));
const STRING = 3;

const commands = [
  {
    name: 'bug',
    description: 'Report a bug (opens a form)',
    options: [{
      name: 'platform', description: 'Which platform are you on?', type: STRING, required: true,
      choices: choices([
        ['Android', 'android'], ['Android TV', 'android-tv'], ['Windows', 'windows'],
        ['macOS', 'macos'], ['Linux', 'linux'], ['iOS', 'ios'],
      ]),
    }],
  },
  {
    name: 'feature',
    description: 'Request a feature (opens a form)',
    options: [{
      name: 'category', description: 'Which part of the app?', type: STRING, required: true,
      choices: choices([
        ['Playback', 'playback'], ['Sources & Addons', 'sources'], ['IPTV', 'iptv'],
        ['UI / UX', 'ui'], ['Integrations', 'integrations'], ['Other', 'other'],
      ]),
    }],
  },
];

const url = `https://discord.com/api/v10/applications/${cfg.appId}/guilds/${cfg.guildId}/commands`;
const res = await fetch(url, {
  method: 'PUT',
  headers: { Authorization: `Bot ${TOKEN}`, 'Content-Type': 'application/json' },
  body: JSON.stringify(commands),
});

if (res.ok) {
  const data = await res.json();
  console.log(`✓ Registered ${data.length} command(s) to guild ${cfg.guildId}: ${data.map((c) => '/' + c.name).join(', ')}`);
} else {
  console.error('✘ Failed', res.status, await res.text());
  process.exit(1);
}
