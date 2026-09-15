[h1]AI Usage Monitor[/h1]

[b]Claude, Codex, ChatGPT, GitHub Copilot, Gemini/Antigravity, Cursor, ZAI, qwen, kimik & more AI quotas — live in your KDE Plasma 6 panel.[/b]

Track Claude Code 5-hour and weekly limits, OpenAI Codex plan limits, Copilot premium requests, Cursor usage, and API balances for OpenRouter, DeepSeek, Kimi/Moonshot, Mistral, Grok/xAI, Z.AI, Kiro and Muse. One widget instead of an AI usage tab for each service.

I got tired of opening a different website or CLI tool every time I wanted to check how much quota I had left. So I built this: a little panel widget that puts every AI service I use right where I can see it — no tabs, no terminal, just a glance.

[b]One glance at your panel tells you exactly how much you've got left.[/b]

---

[b]What it tracks[/b]

Switch between tabs in the popup for each service:
[list]
[*] [b]Claude[/b] — 5-hour session + 7-day weekly windows
[*] [b]Antigravity / Google AI Studio[/b]
[*] [b]OpenAI API[/b]
[*] [b]Grok / xAI[/b]
[*] [b]Mistral AI[/b]   
[*] [b]Kiro[/b] — Monthly credits, from the kiro-cli login or the Kiro IDE
[*] [b]OpenRouter[/b]
[*] [b]Z.AI[/b] — 5-hour token quota + monthly tools quota
[*] [b]GitHub Copilot[/b] — Premium request usage for personally billed plans, plus local Copilot CLI activity stats
[*] [b]DeepSeek[/b] — Current account balance + granted/topped-up split
[*] [b]Kimi[/b] — Kimi Code plan windows from the kimi CLI login, and/or the Moonshot API balance
[*] [b]Muse[/b] — Local Muse Code session stats with an offline spend estimate; plan windows behind an opt-in switch (Meta reports them only on a billed call, so it is off by default)
[*] [b]Cursor[/b] [i](free plan tested)[/i] — Included usage, Auto/API split and on-demand spend, via the cursor-agent or Cursor IDE login
[/list]

[b]Why I like using it[/b]
[list]
[*] [b]Burn-rate ETA[/b] — tells you [i]"↗ ~3h to 100%"[/i] so you can pace yourself instead of getting surprised
[*] [b]Countdown timers[/b] — ticks down to your next quota reset (refreshes every ~5 min to stay friendly to the APIs)
[*] [b]Usage chart[/b] — a smooth, glowing trend graph with 5H / 24H / 7D toggle and hover-scrub (24H shows the whole day's session burn as a sawtooth)
[*] [b]Period comparison[/b] — [i]"+12% vs last week"[/i] at the same point in the cycle
[*] [b]Theme-aware[/b] — follows your Plasma accent by default, or flip on per-service brand colors
[*] [b]Glassmorphism popup[/b] — translucent, blurred, and honestly just nice to look at
[*] [b]Pin a service[/b] — open straight to your most-used tab
[/list]

[b]Panel modes[/b]

Compact percentage readouts right in the taskbar — color-coded (amber at 70%, red at 90%) with an inline spark-line trend. Pill or compact mode, your call.

---

[b]Setup[/b]

Reads your credentials from local config files — nothing leaves your machine except the calls to each provider's own usage API. Refresh interval is configurable (1–30 min, default 5).

Credential notes: Z.AI uses the widget setting, [icode]$ZAI_TOKEN[/icode], or [icode]~/.config/zai/token[/icode]. GitHub Copilot needs no token on a machine already signed in: the Copilot plugin login ([icode]apps.json[/icode]), the Copilot CLI login, or [icode]gh auth token[/icode] is picked up automatically, and the widget setting or [icode]$GITHUB_TOKEN[/icode] still wins when set. A fine-grained token with Plan: read permission additionally unlocks GitHub's documented billing endpoint. The current user endpoint covers personally billed plans, not organization/enterprise-billed usage. DeepSeek uses the widget setting, [icode]$DEEPSEEK_API_KEY[/icode], or [icode]~/.config/deepseek/api-key[/icode]. Kiro, Kimi Code and Cursor need no key: they reuse the kiro-cli, kimi and cursor-agent logins.

[b]Requires Plasma 6.0+.[/b]

---

🐙 Source, setup details & issues → [link=https://github.com/Muddyblack/ai-usage-widget]github.com/Muddyblack/ai-usage-widget[/link]

Built by [b]muddyblack[/b] • MIT licensed

[i](Yeah, I know yet another AI usage widget, but I wanted one for my own NixOS setup that just worked the way I needed it to. If you're in the same boat, here it is.)[/i] 💙
