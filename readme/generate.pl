#!/usr/bin/env perl
#
# Draws the README artwork for AI Usage Widget.
#
#   perl readme/generate.pl
#
# High-fidelity, crisp SVG illustrations of the live KDE Plasma widget UI,
# faithfully matching the current QML codebase and real widget appearance.
#

use strict;
use warnings;
use File::Basename qw(dirname);

my $DIR = dirname($0);

# ── Palette & Fonts ──────────────────────────────────────────────────────────
my %C = (
    bg_top       => "#181922",
    bg_bot       => "#111218",
    card_bg      => "rgba(255, 255, 255, 0.03)",
    card_border  => "rgba(255, 255, 255, 0.08)",
    text         => "#ffffff",
    muted        => "#9ca3af",
    dim          => "#9ca3af",
    faint        => "#6b7280",
    line         => "#2a2d3d",
    danger       => "#ff4d4d",
    warning      => "#ffa64d",
    claude       => "#cc785c",
    antigravity  => "#4285f4",
    google_blue  => "#4285f4",
    google_green => "#22c55e",
    openai       => "#10a37f",
    kiro         => "#9046FF",
    mistral      => "#ff7000",
    openrouter   => "#8b5cf6",
    grok         => "#9ca3af",
    zai          => "#3b82f6",
    copilot      => "#8b5cf6",
    deepseek     => "#4D6BFE",
    kimi         => "#1e3a8a",
    muse         => "#0064e0",
    cursor       => "#e6e6e6",
    cline        => "#e6e6e6",
    overview     => "#38bdf8",
    spend        => "#34d399",
    sessions     => "#a78bfa",
);

my $UI   = 'system-ui,-apple-system,Segoe UI,Noto Sans,Roboto,sans-serif';
my $MONO = 'ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace';

# Mapping to live provider SVGs in package/contents/icons/
my %PROVIDER_ICONS = (
    claude      => "claude-color.svg",
    antigravity => "antigravity-color.svg",
    openai      => "openai.svg",
    kiro        => "kiro.svg",
    mistral     => "mistral-color.svg",
    openrouter  => "openrouter.svg",
    grok        => "grok.svg",
    zai         => "zai.svg",
    copilot     => "githubcopilot.svg",
    deepseek    => "deepseek-color.svg",
    kimi        => "kimi.svg",
    muse        => "muse-color.svg",
    cursor      => "cursor.svg",
    cline       => "cline.svg",
);

# Fallback monochrome paths for tinting (viewBox 24x24)
my %ICONS = (
    claude      => 'M4.709 15.955l4.72-2.647.08-.23-.08-.128H9.2l-.79-.048-2.698-.073-2.339-.097-2.266-.122-.571-.121L0 11.784l.055-.352.48-.321.686.06 1.52.103 2.278.158 1.652.097 2.449.255h.389l.055-.157-.134-.098-.103-.097-2.358-1.596-2.552-1.688-1.336-.972-.724-.491-.364-.462-.158-1.008.656-.722.881.06.225.061.893.686 1.908 1.476 2.491 1.833.365.304.145-.103.019-.073-.164-.274-1.355-2.446-1.446-2.49-.644-1.032-.17-.619a2.97 2.97 0 01-.104-.729L6.283.134 6.696 0l.996.134.42.364.62 1.414 1.002 2.229 1.555 3.03.456.898.243.832.091.255h.158V9.01l.128-1.706.237-2.095.23-2.695.08-.76.376-.91.747-.492.584.28.48.685-.067.444-.286 1.851-.559 2.903-.364 1.942h.212l.243-.242.985-1.306 1.652-2.064.73-.82.85-.904.547-.431h1.033l.76 1.129-.34 1.166-1.064 1.347-.881 1.142-1.264 1.7-.79 1.36.073.11.188-.02 2.856-.606 1.543-.28 1.841-.315.833.388.091.395-.328.807-1.969.486-2.309.462-3.439.813-.042.03.049.061 1.549.146.662.036h1.622l3.02.225.79.522.474.638-.079.485-1.215.62-1.64-.389-3.829-.91-1.312-.329h-.182v.11l1.093 1.068 2.006 1.81 2.509 2.33.127.578-.322.455-.34-.049-2.205-1.657-.851-.747-1.926-1.62h-.128v.17l.444.649 2.345 3.521.122 1.08-.17.353-.608.213-.668-.122-1.374-1.925-1.415-2.167-1.143-1.943-.14.08-.674 7.254-.316.37-.729.28-.607-.461-.322-.747.322-1.476.389-1.924.315-1.53.286-1.9.17-.632-.012-.042-.14.018-1.434 1.967-2.18 2.945-1.726 1.845-.414.164-.717-.37.067-.662.401-.589 2.388-3.036 1.44-1.882.93-1.086-.006-.158h-.055L4.132 18.56l-1.13.146-.487-.456.061-.746.231-.243 1.908-1.312-.006.006z',
    antigravity => 'M21.751 22.607c1.34 1.005 3.35.335 1.508-1.508C17.73 15.74 18.904 1 12.037 1 5.17 1 6.342 15.74.815 21.1c-2.01 2.009.167 2.511 1.507 1.506 5.192-3.517 4.857-9.714 9.715-9.714 4.857 0 4.522 6.197 9.714 9.715z',
    openai      => 'M21.55 10.004a5.416 5.416 0 00-.478-4.501c-1.217-2.09-3.662-3.166-6.05-2.66A5.59 5.59 0 0010.831 1C8.39.995 6.224 2.546 5.473 4.838A5.553 5.553 0 001.76 7.496a5.487 5.487 0 00.691 6.5 5.416 5.416 0 00.477 4.502c1.217 2.09 3.662 3.165 6.05 2.66A5.586 5.586 0 0013.168 23c2.443.006 4.61-1.546 5.361-3.84a5.553 5.553 0 003.715-2.66 5.488 5.488 0 00-.693-6.497v.001zm-8.381 11.558a4.199 4.199 0 01-2.675-.954c.034-.018.093-.05.132-.074l4.44-2.53a.71.71 0 00.364-.623v-6.176l1.877 1.069c.02.01.033.029.036.05v5.115c-.003 2.274-1.87 4.118-4.174 4.123zM4.192 17.78a4.059 4.059 0 01-.498-2.763c.032.02.09.055.131.078l4.44 2.53c.225.13.504.13.73 0l5.42-3.088v2.138a.068.068 0 01-.027.057L9.9 19.288c-1.999 1.136-4.552.46-5.707-1.51h-.001zM3.023 8.216A4.15 4.15 0 015.198 6.41l-.002.151v5.06a.711.711 0 00.364.624l5.42 3.087-1.876 1.07a.067.067 0 01-.063.005l-4.489-2.559c-1.995-1.14-2.679-3.658-1.53-5.63h.001zm15.417 3.54l-5.42-3.088L14.896 7.6a.067.067 0 01.063-.006l4.489 2.557c1.998 1.14 2.683 3.662 1.529 5.633a4.163 4.163 0 01-2.174 1.807V12.38a.71.71 0 00-.363-.623zm1.867-2.773a6.04 6.04 0 00-.132-.078l-4.44-2.53a.731.731 0 00-.729 0l-5.42 3.088V7.325a.068.068 0 01.027-.057L14.1 4.713c2-1.137 4.555-.46 5.707 1.513.487.833.664 1.809.499 2.757h.001zm-11.741 3.81l-1.877-1.068a.065.065 0 01-.036-.051V6.559c.001-2.277 1.873-4.122 4.181-4.12.976 0 1.92.338 2.671.954-.034.018-.092.05-.131.073l-4.44 2.53a.71.71 0 00-.365.623l-.003 6.173v.002zm1.02-2.168L12 9.25l2.414 1.375v2.75L12 14.75l-2.415-1.375v-2.75z',
);

sub write_svg {
    my ($name, $content) = @_;
    open my $fh, '>', "$DIR/$name" or die "$DIR/$name: $!";
    print $fh $content;
    close $fh;
    printf "  %-22s %5d bytes\n", $name, length($content);
}

sub defs_block {
    my $brand_defs = "";
    for my $id (sort keys %PROVIDER_ICONS) {
        my $file = "$DIR/../package/contents/icons/$PROVIDER_ICONS{$id}";
        next unless -f $file;
        open my $fh, "<", $file or next;
        my $raw = do { local $/; <$fh> };
        close $fh;
        my ($svg_attrs) = ($raw =~ /<svg\s+([^>]+)>/i);
        my $attrs = "";
        if ($svg_attrs && $svg_attrs =~ /fill="([^"]+)"/i) {
            $attrs .= qq{ fill="$1"};
        }
        if ($svg_attrs && $svg_attrs =~ /fill-rule="([^"]+)"/i) {
            $attrs .= qq{ fill-rule="$1"};
        }
        my $inner = $raw;
        $inner =~ s/<svg[^>]*>//i;
        $inner =~ s/<\/svg>//i;
        $inner =~ s/<title>[^<]*<\/title>//i;
        $brand_defs .= qq{  <g id="icon-$id"$attrs>\n$inner\n  </g>\n};
    }

    return <<"DEFS";
<defs>
$brand_defs
  <linearGradient id="bgGrad" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0%" stop-color="#181922"/>
    <stop offset="100%" stop-color="#111218"/>
  </linearGradient>
  <linearGradient id="sessionGrad" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0%" stop-color="#e87272"/>
    <stop offset="100%" stop-color="#e05252"/>
  </linearGradient>
  <linearGradient id="weeklyGrad" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0%" stop-color="#f7bc50"/>
    <stop offset="100%" stop-color="#f5a623"/>
  </linearGradient>
  <linearGradient id="blueGrad" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0%" stop-color="#60a5fa"/>
    <stop offset="100%" stop-color="#3b82f6"/>
  </linearGradient>
  <linearGradient id="greenGrad" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0%" stop-color="#34d399"/>
    <stop offset="100%" stop-color="#10a37f"/>
  </linearGradient>
  <linearGradient id="epic-gradient" x1="0%" y1="0%" x2="100%" y2="100%">
    <stop offset="0%" stop-color="#ff007f" />
    <stop offset="35%" stop-color="#a855f7" />
    <stop offset="70%" stop-color="#00f0ff" />
    <stop offset="100%" stop-color="#00ff7f" />
  </linearGradient>
  <linearGradient id="accentAreaGrad" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0%" stop-color="#cc785c" stop-opacity="0.35"/>
    <stop offset="60%" stop-color="#cc785c" stop-opacity="0.10"/>
    <stop offset="100%" stop-color="#cc785c" stop-opacity="0.0"/>
  </linearGradient>

  <!-- Reusable Switch ON -->
  <g id="switch-on">
    <rect width="24" height="13" rx="6.5" fill="#3a86c8"/>
    <circle cx="17.5" cy="6.5" r="4.5" fill="#1e2022" stroke="#3a86c8" stroke-width="1"/>
  </g>
  <!-- Reusable Switch OFF -->
  <g id="switch-off">
    <rect width="24" height="13" rx="6.5" fill="#31363b"/>
    <circle cx="6.5" cy="6.5" r="4.5" fill="#1e2022" stroke="#7f8c8d" stroke-width="1"/>
  </g>
  <!-- Reusable ToolButton Chevron Down -->
  <g id="chevron-down">
    <rect width="18" height="18" rx="3" fill="transparent"/>
    <path d="M 5,7 L 9,11 L 13,7" fill="none" stroke="#9ca3af" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/>
  </g>
  <!-- Reusable ToolButton Chevron Up -->
  <g id="chevron-up">
    <rect width="18" height="18" rx="3" fill="#ffffff" fill-opacity="0.06"/>
    <path d="M 5,11 L 9,7 L 13,11" fill="none" stroke="#ffffff" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/>
  </g>
  <!-- Reusable Eye Icon -->
  <g id="eye-icon">
    <path d="M 0,3 C 3,0 9,0 12,3 C 9,6 3,6 0,3 Z" fill="none" stroke="#9ca3af" stroke-width="1.2" stroke-linejoin="round"/>
    <circle cx="6" cy="3" r="1.5" fill="#9ca3af"/>
  </g>
</defs>
DEFS
}

sub brand_glyph {
    my ($name, $x, $y, $s, $col, $op) = @_;
    $op  //= 1.0;
    my $scale = sprintf("%.4f", $s / 24);
    if (defined $col && $col ne "" && $col =~ /^#/) {
        my $d = $ICONS{$name};
        if ($d) {
            my $fill_rule = ($name eq "openai" || $name eq "openrouter" || $name eq "cursor" || $name eq "cline" || $name eq "copilot") ? ' fill-rule="evenodd"' : '';
            return qq{<g transform="translate($x, $y) scale($scale)" opacity="$op"><path d="$d" fill="$col"$fill_rule/></g>};
        }
    }
    return qq{<g transform="translate($x, $y) scale($scale)" opacity="$op"><use href="#icon-$name"/></g>};
}

# Plasma Action ToolButton (Save/Export, Settings/Configure, Refresh, Back)
sub tool_button {
    my ($type, $x, $y) = @_;
    my $o = qq{<g transform="translate($x, $y)">};
    $o .= qq{<rect width="22" height="22" rx="4" fill="#ffffff" fill-opacity="0.04" stroke="#ffffff" stroke-opacity="0.08" stroke-width="1"/>};
    if ($type eq 'export') {
        # document-save icon
        $o .= qq{<path d="M4 3h11l3 3v13a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zm1 1v4h9V4H5zm2 9v5h8v-5H7z" fill="#9ca3af"/>};
    } elsif ($type eq 'settings') {
        # configure (gear) icon
        $o .= qq{<path d="M11 4a7 7 0 0 0-1.4.14l-.38 1.54a5.5 5.5 0 0 0-1.33.77l-1.46-.62-.99.99.62 1.46c-.32.41-.58.86-.77 1.33l-1.54.38v1.4l1.54.38c.19.47.45.92.77 1.33l-.62 1.46.99.99 1.46-.62c.41.32.86.58 1.33.77l.38 1.54h1.4l.38-1.54c.47-.19.92-.45 1.33-.77l1.46.62.99-.99-.62-1.46c.32-.41.58-.86.77-1.33l1.54-.38v-1.4l-1.54-.38a5.5 5.5 0 0 0-.77-1.33l.62-1.46-.99-.99-1.46.62a5.5 5.5 0 0 0-1.33-.77L12.4 4.14A7 7 0 0 0 11 4zm0 4.5A2.5 2.5 0 1 1 11 13.5 2.5 2.5 0 0 1 11 8.5z" fill="#9ca3af"/>};
    } elsif ($type eq 'back') {
        # arrow-left icon
        $o .= qq{<path d="M14 6l-5 5 5 5M9 11h9" fill="none" stroke="#ffffff" stroke-opacity="0.85" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>};
    } elsif ($type eq 'refresh') {
        # view-refresh icon
        $o .= qq{<path d="M14.65 4.35A6 6 0 1 0 17 9h-1.8a4.2 4.2 0 1 1-1.4-2.88L12 8h5V3l-2.35 2.35z" fill="#9ca3af"/>};
    }
    $o .= qq{</g>};
    return $o;
}

sub header_row {
    my (%a) = @_;
    my ($title, $sub, $brand, $col, $is_settings) = @a{qw(title subtitle brand color is_settings)};
    my $o = qq{<g transform="translate(16, 16)">\n};

    if ($is_settings) {
        $o .= qq{  <g transform="translate(0, 2) scale(0.85)">\n};
        $o .= qq{    <path d="M 3.5,10 A 8.5,8.5 0 0,0 20.5,10 M 6.5,10 A 5.5,5.5 0 0,0 17.5,10" fill="none" stroke="url(#epic-gradient)" stroke-width="1.8" stroke-linecap="round" />\n};
        $o .= qq{    <path d="M 12,2 C 12,6.5 13.5,8 18,8 C 13.5,8 12,9.5 12,14 C 12,9.5 10.5,8 6,8 C 10.5,8 12,6.5 12,2 Z" fill="url(#epic-gradient)" />\n};
        $o .= qq{    <path d="M 18.5,1.5 C 18.5,2.7 18.9,3.1 20.1,3.1 C 18.9,3.1 18.5,3.5 18.5,4.7 C 18.5,3.5 18.1,3.1 16.9,3.1 C 18.1,3.1 18.5,2.7 18.5,1.5 Z" fill="url(#epic-gradient)" />\n};
        $o .= qq{  </g>\n};
        $o .= qq{  <text x="26" y="11" font-family="$UI" font-size="15" font-weight="700" fill="$C{text}">Settings</text>\n};
        $o .= qq{  <text x="26" y="24" font-family="$UI" font-size="9.5" fill="$C{faint}">$sub</text>\n};
        $o .= tool_button('back', 316, 2);
        $o .= tool_button('refresh', 346, 2);
    } elsif ($brand && ($brand eq "overview" || $brand eq "spend" || $brand eq "sessions" || $brand eq "widget")) {
        my $c = $col || $C{$brand} || "#38bdf8";
        $o .= qq{  <g transform="translate(0, 2) scale(0.85)">\n};
        $o .= qq{    <path d="M 3.5,10 A 8.5,8.5 0 0,0 20.5,10 M 6.5,10 A 5.5,5.5 0 0,0 17.5,10" fill="none" stroke="$c" stroke-width="1.8" stroke-linecap="round" />\n};
        $o .= qq{    <path d="M 12,2 C 12,6.5 13.5,8 18,8 C 13.5,8 12,9.5 12,14 C 12,9.5 10.5,8 6,8 C 10.5,8 12,6.5 12,2 Z" fill="$c" />\n};
        $o .= qq{    <path d="M 18.5,1.5 C 18.5,2.7 18.9,3.1 20.1,3.1 C 18.9,3.1 18.5,3.5 18.5,4.7 C 18.5,3.5 18.1,3.1 16.9,3.1 C 18.1,3.1 18.5,2.7 18.5,1.5 Z" fill="$c" />\n};
        $o .= qq{  </g>\n};
        $o .= qq{  <text x="28" y="15" font-family="$UI" font-size="15" font-weight="700" fill="$C{text}">$title</text>\n};
        $o .= tool_button('export', 286, 2);
        $o .= tool_button('settings', 316, 2);
        $o .= tool_button('refresh', 346, 2);
    } else {
        $o .= brand_glyph($brand, 0, 2, 18, "", 1.0);
        $o .= qq{  <text x="28" y="15" font-family="$UI" font-size="15" font-weight="700" fill="$C{text}">$title</text>\n};
        $o .= tool_button('export', 286, 2);
        $o .= tool_button('settings', 316, 2);
        $o .= tool_button('refresh', 346, 2);
    }
    $o .= qq{</g>\n};
    return $o;
}

# Tab bar: supports custom tabs list (with feature tab dots or provider icons)
sub tab_bar {
    my ($active_tab, $custom_tabs) = @_;
    my @tabs = $custom_tabs ? @$custom_tabs : (
        { id => "claude",      brand => "claude" },
        { id => "antigravity", brand => "antigravity" },
        { id => "openai",      brand => "openai" },
        { id => "kiro",        brand => "kiro" },
        { id => "grok",        brand => "grok" },
        { id => "cursor",      brand => "cursor" },
        { id => "cline",       brand => "cline" },
    );

    my $o = qq{<!-- Tab Bar -->\n<g transform="translate(0, 0)">\n};
    my $x = 16;
    my $spacing = 4;
    my $tab_w = sprintf("%.2f", (368 - ($#tabs) * $spacing) / scalar(@tabs));
    for my $i (0 .. $#tabs) {
        my $t = $tabs[$i];
        my $is_active = ($t->{id} eq $active_tab);
        my $bg = $is_active ? "rgba(255,255,255,0.10)" : "transparent";
        my $border = $is_active ? "rgba(255,255,255,0.20)" : "rgba(255,255,255,0.08)";
        my $icon_op = $is_active ? 1.0 : 0.5;
        my $cur_x = sprintf("%.1f", $x + $i * ($tab_w + $spacing));
        my $icon_x = sprintf("%.1f", $cur_x + ($tab_w - 16) / 2);
        my $icon_y = sprintf("%.1f", 52 + (32 - 16) / 2);

        $o .= qq{  <rect x="$cur_x" y="52" width="$tab_w" height="32" rx="6" fill="$bg" stroke="$border" stroke-width="1"/>\n};
        if ($t->{dot}) {
            my $dot_x = sprintf("%.1f", $cur_x + $tab_w / 2);
            my $dot_y = sprintf("%.1f", 52 + 16);
            $o .= qq{  <circle cx="$dot_x" cy="$dot_y" r="4" fill="$t->{dot}" opacity="$icon_op"/>\n};
        } else {
            $o .= qq{  } . brand_glyph($t->{brand}, $icon_x, $icon_y, 16, "", $icon_op) . "\n";
        }
    }
    $o .= qq{</g>\n};
    return $o;
}

sub segmented_bar {
    my (%a) = @_;
    my ($x, $y, $pct, $grad_id, $danger) = @a{qw(x y pct grad danger)};
    my $total_w = 368;
    my $n = 20;
    my $spacing = 3;
    my $seg_w = ($total_w - ($n - 1) * $spacing) / $n;

    my $filled_count = int(($pct / 100) * $n + 0.5);
    my $o = qq{<g transform="translate($x, $y)">\n};
    for my $i (0 .. $n - 1) {
        my $sx = sprintf("%.1f", $i * ($seg_w + $spacing));
        if ($i < $filled_count) {
            my $fill = $danger ? $C{danger} : ($pct >= 90 ? $C{danger} : ($pct >= 70 ? $C{warning} : "url(#$grad_id)"));
            $o .= qq{  <rect x="$sx" y="0" width="$seg_w" height="8" rx="2" fill="$fill"/>\n};
        } else {
            $o .= qq{  <rect x="$sx" y="0" width="$seg_w" height="8" rx="2" fill="#ffffff" fill-opacity="0.06" stroke="#ffffff" stroke-opacity="0.10" stroke-width="1"/>\n};
        }
    }
    $o .= qq{</g>\n};
    return $o;
}

sub popup_row {
    my (%a) = @_;
    my ($y, $label, $reset_text, $countdown, $pct, $grad, $token_text, $eta, $delta, $pct_col) =
        @a{qw(y label reset_text countdown pct grad token_text eta delta pct_color)};
    $pct_col //= ($pct >= 90 ? $C{danger} : ($pct >= 70 ? $C{warning} : $C{text}));

    my $o = qq{<g transform="translate(16, $y)">\n};
    $o .= qq{  <text x="0" y="13" font-family="$UI" font-size="13" font-weight="700" fill="$C{text}">$label</text>\n};
    if ($reset_text) {
        my $rx = 8 + length($label) * 8.5;
        $o .= qq{  <text x="$rx" y="13" font-family="$UI" font-size="11" fill="$C{muted}">· $reset_text</text>\n};
    }
    if ($countdown) {
        my $cd_w = int(length($countdown) * 6.2 + 14);
        my $cd_x = 324 - $cd_w;
        my $cd_text_x = $cd_x + $cd_w / 2;
        $o .= qq{  <rect x="$cd_x" y="0" width="$cd_w" height="18" rx="4" fill="#ffffff" fill-opacity="0.06" stroke="#ffffff" stroke-opacity="0.12" stroke-width="1"/>\n};
        $o .= qq{  <text x="$cd_text_x" y="12.5" text-anchor="middle" font-family="$UI" font-size="9" fill="#d1d5db">$countdown</text>\n};
    }
    $o .= qq{  <text x="368" y="13.5" text-anchor="end" font-family="$UI" font-size="14" font-weight="700" fill="$pct_col">@{[$pct]}%</text>\n};

    if ($eta || $delta) {
        $o .= qq{  <g transform="translate(0, 19)">\n};
        if ($eta) {
            $o .= qq{    <text x="0" y="8" font-family="$UI" font-size="9.5" font-weight="600" fill="$C{warning}">↗ $eta</text>\n};
        }
        if ($delta) {
            $o .= qq{    <text x="368" y="8" text-anchor="end" font-family="$UI" font-size="9.5" fill="$C{dim}">$delta</text>\n};
        }
        $o .= qq{  </g>\n};
        $o .= segmented_bar(x => 0, y => 32, pct => $pct, grad => $grad, danger => ($pct >= 90));
        if ($token_text) {
            $o .= qq{  <text x="0" y="52" font-family="$UI" font-size="9" fill="$C{faint}">$token_text</text>\n};
        }
    } else {
        $o .= segmented_bar(x => 0, y => 22, pct => $pct, grad => $grad, danger => ($pct >= 90));
        if ($token_text) {
            $o .= qq{  <text x="0" y="41" font-family="$UI" font-size="9" fill="$C{faint}">$token_text</text>\n};
        }
    }
    $o .= qq{</g>\n};
    return $o;
}

sub footer_row {
    my ($w, $y, $spend, $time) = @_;
    my $o = qq{<g transform="translate(16, $y)">\n};
    if ($spend) {
        $o .= qq{  <rect x="0" y="-12" width="68" height="16" rx="4" fill="#ffffff" fill-opacity="0.06" stroke="#ffffff" stroke-opacity="0.12" stroke-width="1"/>\n};
        $o .= qq{  <text x="34" y="-1" text-anchor="middle" font-family="$UI" font-size="9" font-weight="700" fill="$C{muted}">Σ \$$spend</text>\n};
    }
    $o .= qq{  <text x="@{[$w - 32]}" y="-1" text-anchor="end" font-family="$UI" font-size="10" fill="$C{muted}">updated $time</text>\n};
    $o .= qq{</g>\n};
    return $o;
}

# ── 1. CLAUDE_USAGE.SVG (Claude Usage - Compact Popup Mode) ─────────────────────
sub make_claude_usage {
    my $w = 400; my $h = 348;
    my $o = qq{<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $w $h" width="$w" height="$h">\n};
    $o .= defs_block();
    $o .= qq{<rect width="$w" height="$h" rx="12" fill="url(#bgGrad)"/>\n};
    $o .= qq{<rect width="$w" height="$h" rx="12" fill="none" stroke="#ffffff" stroke-opacity="0.06" stroke-width="1.2"/>\n};
    $o .= header_row(title => "Claude Usage", brand => "claude", color => $C{claude});
    $o .= tab_bar("claude");

    # User Row matching live screenshot
    $o .= qq{<g transform="translate(16, 96)">\n};
    # User Profile icon (user-identity)
    $o .= qq{  <g transform="translate(0, 0)">\n};
    $o .= qq{    <circle cx="6" cy="5" r="3.2" fill="none" stroke="$C{muted}" stroke-width="1.3"/>\n};
    $o .= qq{    <path d="M1 14c0-2.8 2.2-4.5 5-4.5s5 1.7 5 4.5" fill="none" stroke="$C{muted}" stroke-width="1.3" stroke-linecap="round"/>\n};
    $o .= qq{  </g>\n};
    $o .= qq{  <text x="18" y="11" font-family="$UI" font-size="11" fill="$C{dim}">Default</text>\n};

    # Effort Chip
    $o .= qq{  <rect x="130" y="0" width="66" height="16" rx="3" fill="#ffffff" fill-opacity="0.05" stroke="#ffffff" stroke-opacity="0.14" stroke-width="1"/>\n};
    $o .= qq{  <text x="163" y="11" text-anchor="middle" font-family="$UI" font-size="9" fill="#9ca3af">effort: medium</text>\n};

    # Dream Chip
    $o .= qq{  <rect x="201" y="0" width="46" height="16" rx="3" fill="#ffffff" fill-opacity="0.04" stroke="#ffffff" stroke-opacity="0.10" stroke-width="1"/>\n};
    $o .= qq{  <text x="224" y="11" text-anchor="middle" font-family="$UI" font-size="9" fill="#6b7280">dream: off</text>\n};

    # PRO Badge
    $o .= qq{  <rect x="252" y="0" width="30" height="16" rx="3" fill="#cc785c" fill-opacity="0.12" stroke="#cc785c" stroke-opacity="0.4" stroke-width="1"/>\n};
    $o .= qq{  <text x="267" y="11.5" text-anchor="middle" font-family="$UI" font-size="9" font-weight="700" fill="$C{claude}">PRO</text>\n};

    # StatusChip (• Minor Issues)
    $o .= qq{  <rect x="287" y="0" width="81" height="16" rx="3" fill="#ffa64d" fill-opacity="0.10" stroke="#ffa64d" stroke-opacity="0.35" stroke-width="1"/>\n};
    $o .= qq{  <circle cx="295" cy="8" r="2.5" fill="$C{warning}"/>\n};
    $o .= qq{  <text x="331" y="11" text-anchor="middle" font-family="$UI" font-size="9" font-weight="700" fill="$C{warning}">Minor Issues</text>\n};
    $o .= qq{</g>\n};

    # SubTabBar: Usage (active) / Stats
    $o .= qq{<g transform="translate(16, 122)">\n};
    $o .= qq{  <rect width="368" height="26" rx="6" fill="#ffffff" fill-opacity="0.04" stroke="#ffffff" stroke-opacity="0.07" stroke-width="1"/>\n};
    $o .= qq{  <rect x="2" y="2" width="181" height="22" rx="5" fill="#cc785c" fill-opacity="0.20" stroke="#cc785c" stroke-opacity="0.35" stroke-width="1"/>\n};
    $o .= qq{  <text x="92" y="17" text-anchor="middle" font-family="$UI" font-size="11" font-weight="700" fill="$C{claude}">Usage</text>\n};
    $o .= qq{  <text x="276" y="17" text-anchor="middle" font-family="$UI" font-size="11" fill="$C{dim}">Stats</text>\n};
    $o .= qq{</g>\n};

    # 5 Hours Row
    $o .= popup_row(
        y => 158,
        label => "5 Hours",
        reset_text => "resets 15:00",
        countdown => "in 2h 3m",
        pct => 61,
        grad => "sessionGrad",
        pct_color => "#ff5555",
        eta => "~7.2h to 100%",
        delta => "+44% vs yesterday",
    );

    # 7 Days Row
    $o .= popup_row(
        y => 224,
        label => "7 Days",
        reset_text => "resets Sep 19, 11:00",
        countdown => "in 6d 22h 3m",
        pct => 3,
        grad => "weeklyGrad",
        pct_color => "#ffa64d",
        delta => "-4% vs last week",
    );

    # Estimated model card summary
    $o .= qq{<g transform="translate(16, 290)">\n};
    $o .= qq{  <rect x="0" y="0" width="180" height="24" rx="4" fill="#cc785c" fill-opacity="0.08" stroke="#cc785c" stroke-opacity="0.20" stroke-width="1"/>\n};
    $o .= qq{  <text x="10" y="16" font-family="$UI" font-size="9" fill="$C{muted}">sonnet-4</text>\n};
    $o .= qq{  <text x="170" y="16" text-anchor="end" font-family="$UI" font-size="10.5" font-weight="700" fill="$C{claude}">\$14.20</text>\n};
    $o .= qq{  <rect x="188" y="0" width="180" height="24" rx="4" fill="#cc785c" fill-opacity="0.05" stroke="#cc785c" stroke-opacity="0.14" stroke-width="1"/>\n};
    $o .= qq{  <text x="198" y="16" font-family="$UI" font-size="9" fill="$C{muted}">opus-4</text>\n};
    $o .= qq{  <text x="358" y="16" text-anchor="end" font-family="$UI" font-size="10.5" font-weight="700" fill="$C{dim}">\$0.00</text>\n};
    $o .= qq{</g>\n};

    $o .= footer_row($w, 336, "", "12:31");
    $o .= qq{</svg>\n};
    write_svg('claude_usage.svg', $o);
}

# ── 2. ANTIGRAVITY_USAGE.SVG (Antigravity Usage) ───────────────────────────────
sub make_antigravity_usage {
    my $w = 400; my $h = 398;
    my $o = qq{<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $w $h" width="$w" height="$h">\n};
    $o .= defs_block();
    $o .= qq{<rect width="$w" height="$h" rx="12" fill="url(#bgGrad)"/>\n};
    $o .= qq{<rect width="$w" height="$h" rx="12" fill="none" stroke="#ffffff" stroke-opacity="0.06" stroke-width="1.2"/>\n};
    $o .= header_row(title => "Antigravity Usage", brand => "antigravity", color => $C{antigravity});
    $o .= tab_bar("antigravity");

    # User Row matching AntigravityTab.qml
    $o .= qq{<g transform="translate(16, 96)">\n};
    $o .= qq{  <g transform="translate(0, 0)">\n};
    $o .= qq{    <circle cx="6" cy="5" r="3.2" fill="none" stroke="$C{antigravity}" stroke-width="1.3"/>\n};
    $o .= qq{    <path d="M1 14c0-2.8 2.2-4.5 5-4.5s5 1.7 5 4.5" fill="none" stroke="$C{antigravity}" stroke-width="1.3" stroke-linecap="round"/>\n};
    $o .= qq{  </g>\n};
    $o .= qq{  <text x="18" y="11" font-family="$UI" font-size="10.5" fill="$C{muted}">sample.user\@gmail.com</text>\n};
    $o .= qq{  <rect x="202" y="-1" width="86" height="18" rx="4" fill="#22c55e" fill-opacity="0.12" stroke="#22c55e" stroke-opacity="0.3" stroke-width="1"/>\n};
    $o .= qq{  <text x="245" y="11.5" text-anchor="middle" font-family="$UI" font-size="8.5" font-weight="700" fill="#22c55e">Google AI Pro</text>\n};
    $o .= qq{  <rect x="294" y="-1" width="74" height="18" rx="3" fill="#22c55e" fill-opacity="0.12" stroke="#22c55e" stroke-opacity="0.30" stroke-width="1"/>\n};
    $o .= qq{  <circle cx="304" cy="8" r="2.5" fill="#22c55e"/>\n};
    $o .= qq{  <text x="312" y="11.5" font-family="$UI" font-size="9" font-weight="600" fill="#22c55e">Operational</text>\n};
    $o .= qq{</g>\n};

    # Prompt Credits Row (Standard PopupRow style matching real QML)
    $o .= popup_row(
        y => 124,
        label => "Prompt Credits",
        reset_text => "resets in 18d 4h",
        countdown => "in 18d 4h",
        pct => 42,
        grad => "blueGrad",
        pct_color => $C{antigravity},
        token_text => "29.0K / 50.0K left",
    );

    # Model Quotas Section (Pooled families from AntigravityTab.qml!)
    $o .= qq{<g transform="translate(16, 192)">\n};
    $o .= qq{  <rect x="0" y="0" width="368" height="1" fill="$C{line}"/>\n};
    $o .= qq{  <text x="0" y="18" font-family="$UI" font-size="11" font-weight="700" fill="$C{dim}">Model Quotas</text>\n};

    # Family 1: Gemini Models (Pooled 5-hour window)
    $o .= qq{  <g transform="translate(0, 32)">\n};
    $o .= qq{    <circle cx="4" cy="5" r="3.5" fill="$C{google_blue}"/>\n};
    $o .= qq{    <text x="14" y="9" font-family="$UI" font-size="10.5" font-weight="700" fill="$C{text}">Gemini Models</text>\n};
    $o .= qq{    <text x="96" y="9" font-family="$UI" font-size="9" fill="$C{faint}">· resets in 2h 42m</text>\n};
    $o .= qq{    <text x="368" y="9" text-anchor="end" font-family="$UI" font-size="10.5" font-weight="700" fill="$C{google_blue}">38%</text>\n};

    # Sub-rows for Gemini
    $o .= qq{    <g transform="translate(14, 18)">\n};
    $o .= qq{      <text x="0" y="8" font-family="$UI" font-size="9.5" fill="#c0caf5">Gemini 2.5 Flash</text>\n};
    $o .= qq{      <rect x="130" y="2" width="190" height="6" rx="3" fill="#ffffff" fill-opacity="0.06" stroke="#ffffff" stroke-opacity="0.10" stroke-width="1"/>\n};
    $o .= qq{      <rect x="131" y="3" width="66" height="4" rx="2" fill="$C{google_blue}"/>\n};
    $o .= qq{      <text x="354" y="8" text-anchor="end" font-family="$UI" font-size="9.5" font-weight="700" fill="$C{google_blue}">35%</text>\n};
    $o .= qq{    </g>\n};

    $o .= qq{    <g transform="translate(14, 34)">\n};
    $o .= qq{      <text x="0" y="8" font-family="$UI" font-size="9.5" fill="#c0caf5">Gemini 2.5 Pro</text>\n};
    $o .= qq{      <rect x="130" y="2" width="190" height="6" rx="3" fill="#ffffff" fill-opacity="0.06" stroke="#ffffff" stroke-opacity="0.10" stroke-width="1"/>\n};
    $o .= qq{      <rect x="131" y="3" width="80" height="4" rx="2" fill="$C{google_blue}"/>\n};
    $o .= qq{      <text x="354" y="8" text-anchor="end" font-family="$UI" font-size="9.5" font-weight="700" fill="$C{google_blue}">42%</text>\n};
    $o .= qq{    </g>\n};
    $o .= qq{  </g>\n};

    # Family 2: Claude & GPT Models (Pooled quota)
    $o .= qq{  <g transform="translate(0, 94)">\n};
    $o .= qq{    <circle cx="4" cy="5" r="3.5" fill="$C{google_green}"/>\n};
    $o .= qq{    <text x="14" y="9" font-family="$UI" font-size="10.5" font-weight="700" fill="$C{text}">Claude &amp; GPT Models</text>\n};
    $o .= qq{    <text x="136" y="9" font-family="$UI" font-size="9" fill="$C{faint}">· resets in 3h 15m</text>\n};
    $o .= qq{    <text x="368" y="9" text-anchor="end" font-family="$UI" font-size="10.5" font-weight="700" fill="$C{google_green}">55%</text>\n};

    $o .= qq{    <g transform="translate(14, 18)">\n};
    $o .= qq{      <text x="0" y="8" font-family="$UI" font-size="9.5" fill="#c0caf5">Claude 3.7 Sonnet</text>\n};
    $o .= qq{      <rect x="130" y="2" width="190" height="6" rx="3" fill="#ffffff" fill-opacity="0.06" stroke="#ffffff" stroke-opacity="0.10" stroke-width="1"/>\n};
    $o .= qq{      <rect x="131" y="3" width="114" height="4" rx="2" fill="$C{google_green}"/>\n};
    $o .= qq{      <text x="354" y="8" text-anchor="end" font-family="$UI" font-size="9.5" font-weight="700" fill="$C{google_green}">60%</text>\n};
    $o .= qq{    </g>\n};

    $o .= qq{    <g transform="translate(14, 34)">\n};
    $o .= qq{      <text x="0" y="8" font-family="$UI" font-size="9.5" fill="#c0caf5">GPT-4o</text>\n};
    $o .= qq{      <rect x="130" y="2" width="190" height="6" rx="3" fill="#ffffff" fill-opacity="0.06" stroke="#ffffff" stroke-opacity="0.10" stroke-width="1"/>\n};
    $o .= qq{      <rect x="131" y="3" width="95" height="4" rx="2" fill="$C{google_green}"/>\n};
    $o .= qq{      <text x="354" y="8" text-anchor="end" font-family="$UI" font-size="9.5" font-weight="700" fill="$C{google_green}">50%</text>\n};
    $o .= qq{    </g>\n};
    $o .= qq{  </g>\n};

    $o .= qq{</g>\n};

    $o .= footer_row($w, 380, "", "11:43");
    $o .= qq{</svg>\n};
    write_svg('antigravity_usage.svg', $o);
}

# ── 3. OPENAI_USAGE.SVG (OpenAI Usage) ────────────────────────────────────────
sub make_openai_usage {
    my $w = 400; my $h = 360;
    my $o = qq{<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $w $h" width="$w" height="$h">\n};
    $o .= defs_block();
    $o .= qq{<rect width="$w" height="$h" rx="12" fill="url(#bgGrad)"/>\n};
    $o .= qq{<rect width="$w" height="$h" rx="12" fill="none" stroke="#ffffff" stroke-opacity="0.06" stroke-width="1.2"/>\n};
    $o .= header_row(title => "OpenAI Usage", brand => "openai", color => $C{openai});
    $o .= tab_bar("openai");

    # SubTabBar (Usage / Stats) matching OpenAiTab.qml
    $o .= qq{<g transform="translate(16, 94)">\n};
    $o .= qq{  <rect width="368" height="26" rx="6" fill="#ffffff" fill-opacity="0.04" stroke="#ffffff" stroke-opacity="0.07" stroke-width="1"/>\n};
    $o .= qq{  <rect x="2" y="2" width="181" height="22" rx="5" fill="#10a37f" fill-opacity="0.20" stroke="#10a37f" stroke-opacity="0.35" stroke-width="1"/>\n};
    $o .= qq{  <text x="92" y="17" text-anchor="middle" font-family="$UI" font-size="11" font-weight="700" fill="#10a37f">Usage</text>\n};
    $o .= qq{  <text x="276" y="17" text-anchor="middle" font-family="$UI" font-size="11" fill="#ffffff" fill-opacity="0.6">Stats</text>\n};
    $o .= qq{</g>\n};

    # User Row matching OpenAiTab.qml
    $o .= qq{<g transform="translate(16, 130)">\n};
    $o .= qq{  <g transform="translate(0, 0)">\n};
    $o .= qq{    <circle cx="6" cy="5" r="3.2" fill="none" stroke="$C{openai}" stroke-width="1.3"/>\n};
    $o .= qq{    <path d="M1 14c0-2.8 2.2-4.5 5-4.5s5 1.7 5 4.5" fill="none" stroke="$C{openai}" stroke-width="1.3" stroke-linecap="round"/>\n};
    $o .= qq{  </g>\n};
    $o .= qq{  <text x="18" y="11" font-family="$UI" font-size="10.5" fill="$C{muted}">sample.user\@openai.com</text>\n};

    # Codex live model chip (real QML feature)
    $o .= qq{  <rect x="156" y="0" width="46" height="16" rx="8" fill="#10a37f" fill-opacity="0.15" stroke="#10a37f" stroke-opacity="0.35" stroke-width="1"/>\n};
    $o .= qq{  <text x="179" y="11" text-anchor="middle" font-family="$UI" font-size="8.5" font-weight="700" fill="$C{openai}">gpt-4o</text>\n};

    # Effort chip (warning amber for medium effort as in OpenAiTab.qml)
    $o .= qq{  <rect x="206" y="0" width="58" height="16" rx="8" fill="#f59e0b" fill-opacity="0.15" stroke="#f59e0b" stroke-opacity="0.35" stroke-width="1"/>\n};
    $o .= qq{  <text x="235" y="11" text-anchor="middle" font-family="$UI" font-size="8.5" font-weight="700" fill="#ffa64d">effort: med</text>\n};

    # PROLITE badge
    $o .= qq{  <rect x="268" y="-1" width="48" height="18" rx="4" fill="#10a37f" fill-opacity="0.18" stroke="#10a37f" stroke-opacity="0.35" stroke-width="1"/>\n};
    $o .= qq{  <text x="292" y="11.5" text-anchor="middle" font-family="$UI" font-size="8.5" font-weight="700" fill="$C{openai}">PROLITE</text>\n};

    # StatusChip pill matching StatusChip.qml
    $o .= qq{  <rect x="320" y="-1" width="48" height="18" rx="3" fill="#22c55e" fill-opacity="0.12" stroke="#22c55e" stroke-opacity="0.30" stroke-width="1"/>\n};
    $o .= qq{  <circle cx="328" cy="8" r="2.5" fill="#22c55e"/>\n};
    $o .= qq{  <text x="348" y="11.5" text-anchor="middle" font-family="$UI" font-size="8.5" font-weight="600" fill="#22c55e">OK</text>\n};
    $o .= qq{</g>\n};

    # 5 Hours Row (Codex session rate limit)
    $o .= popup_row(
        y => 158,
        label => "5 Hours",
        countdown => "in 2h 40m",
        pct => 20,
        grad => "greenGrad",
        pct_color => $C{openai},
        token_text => "80% of messages left",
    );

    # Weekly Row (Codex weekly limit)
    $o .= popup_row(
        y => 222,
        label => "Weekly",
        countdown => "in 6d 11h",
        pct => 3,
        grad => "greenGrad",
        pct_color => $C{openai},
        token_text => "97% of messages left",
    );

    # Footnote
    $o .= qq{<g transform="translate(16, 292)">\n};
    $o .= qq{  <text x="0" y="8" font-family="$UI" font-size="9" fill="$C{faint}">Plan limits above. Add an OpenAI API key in settings for API token/cost data.</text>\n};
    $o .= qq{</g>\n};

    $o .= footer_row($w, 342, "6.80", "09:20");
    $o .= qq{</svg>\n};
    write_svg('openai_usage.svg', $o);
}

# ── 4. USAGE_CHART.SVG (Usage Chart Feature - Pixel-Perfect to Live Screenshot) ─
sub make_usage_chart {
    my $w = 400; my $h = 516;
    my $o = qq{<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $w $h" width="$w" height="$h">\n};
    $o .= defs_block();
    $o .= qq{<rect width="$w" height="$h" rx="12" fill="url(#bgGrad)"/>\n};
    $o .= qq{<rect width="$w" height="$h" rx="12" fill="none" stroke="#ffffff" stroke-opacity="0.06" stroke-width="1.2"/>\n};
    $o .= header_row(title => "Claude Usage", brand => "claude", color => $C{claude});
    $o .= tab_bar("claude");

    # User Row matching live screenshot
    $o .= qq{<g transform="translate(16, 96)">\n};
    # User Profile icon
    $o .= qq{  <g transform="translate(0, 0)">\n};
    $o .= qq{    <circle cx="6" cy="5" r="3.2" fill="none" stroke="$C{muted}" stroke-width="1.3"/>\n};
    $o .= qq{    <path d="M1 14c0-2.8 2.2-4.5 5-4.5s5 1.7 5 4.5" fill="none" stroke="$C{muted}" stroke-width="1.3" stroke-linecap="round"/>\n};
    $o .= qq{  </g>\n};
    $o .= qq{  <text x="18" y="11" font-family="$UI" font-size="11" fill="$C{dim}">Default</text>\n};

    # Effort Chip
    $o .= qq{  <rect x="130" y="0" width="66" height="16" rx="3" fill="#ffffff" fill-opacity="0.05" stroke="#ffffff" stroke-opacity="0.14" stroke-width="1"/>\n};
    $o .= qq{  <text x="163" y="11" text-anchor="middle" font-family="$UI" font-size="9" fill="#9ca3af">effort: medium</text>\n};

    # Dream Chip
    $o .= qq{  <rect x="201" y="0" width="46" height="16" rx="3" fill="#ffffff" fill-opacity="0.04" stroke="#ffffff" stroke-opacity="0.10" stroke-width="1"/>\n};
    $o .= qq{  <text x="224" y="11" text-anchor="middle" font-family="$UI" font-size="9" fill="#6b7280">dream: off</text>\n};

    # PRO Badge
    $o .= qq{  <rect x="252" y="0" width="30" height="16" rx="3" fill="#cc785c" fill-opacity="0.12" stroke="#cc785c" stroke-opacity="0.4" stroke-width="1"/>\n};
    $o .= qq{  <text x="267" y="11.5" text-anchor="middle" font-family="$UI" font-size="9" font-weight="700" fill="$C{claude}">PRO</text>\n};

    # StatusChip (• Minor Issues)
    $o .= qq{  <rect x="287" y="0" width="81" height="16" rx="3" fill="#ffa64d" fill-opacity="0.10" stroke="#ffa64d" stroke-opacity="0.35" stroke-width="1"/>\n};
    $o .= qq{  <circle cx="295" cy="8" r="2.5" fill="$C{warning}"/>\n};
    $o .= qq{  <text x="331" y="11" text-anchor="middle" font-family="$UI" font-size="9" font-weight="700" fill="$C{warning}">Minor Issues</text>\n};
    $o .= qq{</g>\n};

    # SubTabBar: Usage (active) / Stats
    $o .= qq{<g transform="translate(16, 122)">\n};
    $o .= qq{  <rect width="368" height="26" rx="6" fill="#ffffff" fill-opacity="0.04" stroke="#ffffff" stroke-opacity="0.07" stroke-width="1"/>\n};
    $o .= qq{  <rect x="2" y="2" width="181" height="22" rx="5" fill="#cc785c" fill-opacity="0.20" stroke="#cc785c" stroke-opacity="0.35" stroke-width="1"/>\n};
    $o .= qq{  <text x="92" y="17" text-anchor="middle" font-family="$UI" font-size="11" font-weight="700" fill="$C{claude}">Usage</text>\n};
    $o .= qq{  <text x="276" y="17" text-anchor="middle" font-family="$UI" font-size="11" fill="$C{dim}">Stats</text>\n};
    $o .= qq{</g>\n};

    # 5 Hours Row
    $o .= popup_row(
        y => 158,
        label => "5 Hours",
        reset_text => "resets 15:00",
        countdown => "in 2h 3m",
        pct => 61,
        grad => "sessionGrad",
        pct_color => "#ff5555",
        eta => "~7.2h to 100%",
        delta => "+44% vs yesterday",
    );

    # 7 Days Row
    $o .= popup_row(
        y => 220,
        label => "7 Days",
        reset_text => "resets Sep 19, 11:00",
        countdown => "in 6d 22h 3m",
        pct => 3,
        grad => "weeklyGrad",
        pct_color => "#ffa64d",
        delta => "-4% vs last week",
    );

    # Usage Chart Section (matching live QML UsageChart.qml)
    $o .= qq{<g transform="translate(16, 282)">\n};
    $o .= qq{  <rect width="368" height="188" rx="8" fill="#ffffff" fill-opacity="0.02" stroke="#ffffff" stroke-opacity="0.06" stroke-width="1"/>\n};

    # Chart Header: Date range + Granularity buttons
    $o .= qq{  <g transform="translate(8, 8)">\n};
    $o .= qq{    <rect width="96" height="18" rx="4" fill="#ffffff" fill-opacity="0.04"/>\n};
    $o .= qq{    <text x="7" y="12.5" font-family="$UI" font-size="9" fill="$C{faint}">‹</text>\n};
    $o .= qq{    <text x="48" y="12" text-anchor="middle" font-family="$UI" font-size="8.5" font-weight="700" fill="#d1d5db">Sep 5 - Sep 12</text>\n};
    $o .= qq{    <text x="89" y="12.5" font-family="$UI" font-size="9" fill="$C{faint}">›</text>\n};

    # Granularity Switcher: 5H, 24H, 7D (active), 30D
    $o .= qq{    <g transform="translate(236, 0)">\n};
    $o .= qq{      <rect x="0" y="0" width="26" height="18" rx="3" fill="#ffffff" fill-opacity="0.04"/>\n};
    $o .= qq{      <text x="13" y="12" text-anchor="middle" font-family="$UI" font-size="8.5" fill="$C{faint}">5H</text>\n};
    $o .= qq{      <rect x="29" y="0" width="28" height="18" rx="3" fill="#ffffff" fill-opacity="0.04"/>\n};
    $o .= qq{      <text x="43" y="12" text-anchor="middle" font-family="$UI" font-size="8.5" fill="$C{faint}">24H</text>\n};
    # 7D Active
    $o .= qq{      <rect x="60" y="0" width="26" height="18" rx="3" fill="#cc785c" fill-opacity="0.8"/>\n};
    $o .= qq{      <text x="73" y="12" text-anchor="middle" font-family="$UI" font-size="8.5" font-weight="700" fill="#ffffff">7D</text>\n};
    $o .= qq{      <rect x="89" y="0" width="28" height="18" rx="3" fill="#ffffff" fill-opacity="0.04"/>\n};
    $o .= qq{      <text x="103" y="12" text-anchor="middle" font-family="$UI" font-size="8.5" fill="$C{faint}">30D</text>\n};
    $o .= qq{    </g>\n};
    $o .= qq{  </g>\n};

    # Chart Canvas
    $o .= qq{  <g transform="translate(0, 0)">\n};
    # Y-axis labels & dashed gridlines
    $o .= qq{    <text x="10" y="52" font-family="$UI" font-size="8" fill="$C{faint}">100%</text>\n};
    $o .= qq{    <line x1="38" y1="49" x2="356" y2="49" stroke="#ffffff" stroke-opacity="0.08" stroke-dasharray="3,3" stroke-width="1"/>\n};

    $o .= qq{    <text x="14" y="99" font-family="$UI" font-size="8" fill="$C{faint}">50%</text>\n};
    $o .= qq{    <line x1="38" y1="96" x2="356" y2="96" stroke="#ffffff" stroke-opacity="0.08" stroke-dasharray="3,3" stroke-width="1"/>\n};

    $o .= qq{    <text x="18" y="146" font-family="$UI" font-size="8" fill="$C{faint}">0%</text>\n};
    $o .= qq{    <line x1="38" y1="143" x2="356" y2="143" stroke="#ffffff" stroke-opacity="0.08" stroke-dasharray="3,3" stroke-width="1"/>\n};

    # Area Fill & Smooth Curve matching screenshot
    my $curve_path = "M 160 138 C 166 128, 180 125, 204 124 C 226 122, 242 116, 260 102 C 276 90, 288 90, 306 80 C 320 72, 328 56, 338 48 L 346 48 L 346 143";
    $o .= qq{    <path d="$curve_path L 160 143 Z" fill="url(#accentAreaGrad)"/>\n};
    # Curve Glow
    $o .= qq{    <path d="$curve_path" fill="none" stroke="#cc785c" stroke-width="6" opacity="0.32" stroke-linecap="round"/>\n};
    # Curve Line
    $o .= qq{    <path d="$curve_path" fill="none" stroke="#e08668" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>\n};

    # Reset annotation
    $o .= qq{    <text x="332" y="40" text-anchor="middle" font-family="$UI" font-size="8" fill="#d1d5db">week reset</text>\n};
    $o .= qq{    <circle cx="346" cy="143" r="2.5" fill="#ffffff"/>\n};
    $o .= qq{    <circle cx="346" cy="143" r="4.5" fill="none" stroke="#e08668" stroke-width="1"/>\n};

    # X-axis timestamps
    $o .= qq{    <text x="42" y="162" font-family="$UI" font-size="8.5" fill="$C{dim}">Sep 5</text>\n};
    $o .= qq{    <text x="42" y="173" font-family="$UI" font-size="8" fill="$C{faint}">12:34</text>\n};
    $o .= qq{    <text x="350" y="167" text-anchor="end" font-family="$UI" font-size="8.5" fill="$C{dim}">Sep 12</text>\n};
    $o .= qq{  </g>\n};
    $o .= qq{</g>\n};

    $o .= footer_row($w, 502, "", "12:31");
    $o .= qq{</svg>\n};
    write_svg('usage_chart.svg', $o);
}

# ── 5. SETTINGS.SVG (Complete 14 Provider Settings Panel) ─────────────────────
sub make_settings {
    my $w = 400; my $h = 512;
    my $o = qq{<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $w $h" width="$w" height="$h">\n};
    $o .= defs_block();
    $o .= qq{<rect width="$w" height="$h" rx="12" fill="url(#bgGrad)"/>\n};
    $o .= qq{<rect width="$w" height="$h" rx="12" fill="none" stroke="#ffffff" stroke-opacity="0.06" stroke-width="1.2"/>\n};
    $o .= header_row(title => "Settings", subtitle => "Turn providers on and set their keys", is_settings => 1);

    # Navigation Tabs (Providers, Appearance, Data, Advanced)
    $o .= qq{<g transform="translate(16, 52)">\n};
    $o .= qq{  <rect width="368" height="26" rx="6" fill="#ffffff" fill-opacity="0.04" stroke="#ffffff" stroke-opacity="0.07" stroke-width="1"/>\n};
    $o .= qq{  <rect x="2" y="2" width="89" height="22" rx="4" fill="#3a86c8" fill-opacity="0.22" stroke="#3a86c8" stroke-opacity="0.4" stroke-width="1"/>\n};
    $o .= qq{  <text x="46.5" y="17" font-family="$UI" font-size="11" font-weight="700" fill="#3a86c8" text-anchor="middle">Providers</text>\n};
    $o .= qq{  <text x="137.5" y="17" font-family="$UI" font-size="11" fill="$C{dim}" text-anchor="middle">Appearance</text>\n};
    $o .= qq{  <text x="228.5" y="17" font-family="$UI" font-size="11" fill="$C{dim}" text-anchor="middle">Data</text>\n};
    $o .= qq{  <text x="320.5" y="17" font-family="$UI" font-size="11" fill="$C{dim}" text-anchor="middle">Advanced</text>\n};
    $o .= qq{</g>\n};

    # Providers List (Full 14 providers from main.qml including Cursor & Cline!)
    my @p_list = (
        { id => "claude",      name => "Claude",      col => $C{claude},      on => 1, expanded => 1 },
        { id => "antigravity", name => "Antigravity", col => $C{antigravity}, on => 1 },
        { id => "openai",      name => "OpenAI",      col => $C{openai},      on => 1, key_set => 1 },
        { id => "kiro",        name => "Kiro",        col => $C{kiro},        on => 1 },
        { id => "mistral",     name => "Mistral",     col => $C{mistral},     on => 0 },
        { id => "openrouter",  name => "OpenRouter",  col => $C{openrouter},  on => 0 },
        { id => "grok",        name => "Grok",        col => $C{grok},        on => 1, key_set => 1 },
        { id => "zai",         name => "Z.AI",        col => $C{zai},         on => 0 },
        { id => "copilot",     name => "Copilot",     col => $C{copilot},     on => 1, key_set => 1 },
        { id => "deepseek",    name => "DeepSeek",    col => $C{deepseek},    on => 0 },
        { id => "kimi",        name => "Kimi",        col => $C{kimi},        on => 0 },
        { id => "muse",        name => "Muse",        col => $C{muse},        tristate => "local" },
        { id => "cursor",      name => "Cursor",      col => $C{cursor},      on => 1 },
        { id => "cline",       name => "Cline",       col => $C{cline},       on => 0 },
    );

    my $py = 92;
    for my $p (@p_list) {
        $o .= qq{<g transform="translate(0, $py)">\n};
        $o .= qq{  <circle cx="20" cy="10" r="3.5" fill="$p->{col}"} . ($p->{on} || $p->{tristate} ? '' : ' opacity="0.35"') . qq{/>\n};
        my $t_col = ($p->{on} || $p->{tristate}) ? $C{text} : $C{dim};
        my $t_w = $p->{expanded} ? qq{ font-weight="700"} : "";
        $o .= qq{  <text x="32" y="14" font-family="$UI" font-size="11"$t_w fill="$t_col">$p->{name}</text>\n};

        if ($p->{tristate}) {
            # Tristate control for Muse
            $o .= qq{  <g transform="translate(120, 0)">\n};
            $o .= qq{    <rect width="168" height="20" rx="4" fill="#ffffff" fill-opacity="0.04" stroke="#ffffff" stroke-opacity="0.07" stroke-width="1"/>\n};
            $o .= qq{    <text x="28" y="14" font-family="$UI" font-size="9.5" fill="#9ca3af" text-anchor="middle">Off</text>\n};
            $o .= qq{    <rect x="57" y="2" width="54" height="16" rx="3" fill="#0064e0" fill-opacity="0.25" stroke="#0064e0" stroke-opacity="0.45" stroke-width="1"/>\n};
            $o .= qq{    <text x="84" y="14" font-family="$UI" font-size="9.5" font-weight="700" fill="#4fa2f5" text-anchor="middle">Local</text>\n};
            $o .= qq{    <text x="140" y="14" font-family="$UI" font-size="9.5" fill="#9ca3af" text-anchor="middle">Live</text>\n};
            $o .= qq{  </g>\n};
            $o .= qq{  <use href="#chevron-down" x="366" y="1"/>\n};
            $py += 25;
        } elsif ($p->{expanded}) {
            $o .= qq{  <use href="#switch-on" x="120" y="4"/>\n};
            $o .= qq{  <use href="#chevron-up" x="366" y="1"/>\n};
            # Expanded API Key Row
            $o .= qq{  <g transform="translate(0, 23)">\n};
            $o .= qq{    <text x="29" y="14" font-family="$UI" font-size="10" fill="$C{dim}">API key</text>\n};
            $o .= qq{    <rect x="108" y="1" width="244" height="20" rx="3" fill="#13141a" stroke="#ffffff" stroke-opacity="0.12" stroke-width="1"/>\n};
            $o .= qq{    <text x="116" y="14" font-family="$MONO" font-size="9" fill="$C{faint}">sk-ant-api03-••••••••••••••••</text>\n};
            $o .= qq{    <rect x="358" y="1" width="24" height="20" rx="3" fill="#ffffff" fill-opacity="0.04" stroke="#ffffff" stroke-opacity="0.08" stroke-width="1"/>\n};
            $o .= qq{    <use href="#eye-icon" x="364" y="8"/>\n};
            $o .= qq{  </g>\n};
            $py += 48;
        } else {
            my $sw = $p->{on} ? "#switch-on" : "#switch-off";
            $o .= qq{  <use href="$sw" x="120" y="4"/>\n};
            if ($p->{key_set}) {
                $o .= qq{  <text x="358" y="13" font-family="$UI" font-size="9" fill="$C{faint}" text-anchor="end">key set</text>\n};
                $o .= qq{  <use href="#chevron-down" x="366" y="1"/>\n};
            }
            $py += 24;
        }
        $o .= qq{</g>\n};
    }

    # Footer Tip
    $o .= qq{<g transform="translate(16, @{[$py + 8]})">\n};
    $o .= qq{  <text x="0" y="9" font-family="$UI" font-size="8.8" fill="$C{faint}">Expand a provider for its API key and options. Keys are optional wherever a local</text>\n};
    $o .= qq{  <text x="0" y="21" font-family="$UI" font-size="8.8" fill="$C{faint}">CLI login can be read instead.</text>\n};
    $o .= qq{</g>\n};

    $o .= qq{</svg>\n};
    write_svg('settings.svg', $o);
}

# ── 6. CLAUDE_PILL.SVG (Claude Panel Pill) ──────────────────────────────────
sub make_claude_pill {
    my $w = 124; my $h = 24;
    my $o = qq{<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $w $h" width="$w" height="$h">\n};
    $o .= defs_block();
    $o .= qq{  <rect width="$w" height="$h" rx="12" fill="#1e1e2e" fill-opacity="0.45" stroke="#ffffff" stroke-opacity="0.08" stroke-width="1"/>\n};

    # Slot 1: Claude 5h (61%)
    $o .= qq{  <g transform="translate(8, 4)">\n};
    $o .= brand_glyph('claude', 0, 0, 16, "", 1.0);
    $o .= qq{    <text x="22" y="12" font-family="$UI" font-size="11" font-weight="700" fill="$C{text}">61%</text>\n};
    $o .= qq{  </g>\n};

    # Divider
    $o .= qq{  <line x1="60" y1="5" x2="60" y2="19" stroke="#ffffff" stroke-opacity="0.16" stroke-width="1"/>\n};

    # Slot 2: Claude 7d (3% - Weekly color tint)
    $o .= qq{  <g transform="translate(68, 4)">\n};
    $o .= brand_glyph('claude', 0, 0, 16, $C{warning}, 1.0);
    $o .= qq{    <text x="22" y="12" font-family="$UI" font-size="11" font-weight="700" fill="$C{text}">3%</text>\n};
    $o .= qq{  </g>\n};

    $o .= qq{</svg>\n};
    write_svg('claude_pill.svg', $o);
}

# ── 7. AGY_PILL.SVG (Antigravity Dual-Slot Panel Pill matching screenshot) ───
sub make_agy_pill {
    my $w = 128; my $h = 24;
    my $o = qq{<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $w $h" width="$w" height="$h">\n};
    $o .= defs_block();
    $o .= qq{  <rect width="$w" height="$h" rx="12" fill="#1e1e2e" fill-opacity="0.45" stroke="#ffffff" stroke-opacity="0.08" stroke-width="1"/>\n};

    # Slot 1: Antigravity Google Gemini (18% - Rainbow arch)
    $o .= qq{  <g transform="translate(8, 4)">\n};
    $o .= brand_glyph('antigravity', 0, 0, 16, "", 1.0);
    $o .= qq{    <text x="22" y="12" font-family="$UI" font-size="11" font-weight="700" fill="$C{text}">18%</text>\n};
    $o .= qq{  </g>\n};

    # Divider
    $o .= qq{  <line x1="62" y1="5" x2="62" y2="19" stroke="#ffffff" stroke-opacity="0.16" stroke-width="1"/>\n};

    # Slot 2: Antigravity External Claude/GPT (36% - Green arch)
    $o .= qq{  <g transform="translate(70, 4)">\n};
    $o .= brand_glyph('antigravity', 0, 0, 16, $C{google_green}, 1.0);
    $o .= qq{    <text x="22" y="12" font-family="$UI" font-size="11" font-weight="700" fill="$C{text}">36%</text>\n};
    $o .= qq{  </g>\n};

    $o .= qq{</svg>\n};
    write_svg('agy_pill.svg', $o);
}

# ── 8. OVERVIEW_TAB.SVG (Overview / General Tab) ─────────────────────────────
sub make_overview_tab {
    my $w = 400; my $h = 560;
    my $o = qq{<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $w $h" width="$w" height="$h">\n};
    $o .= defs_block();
    $o .= qq{<rect width="$w" height="$h" rx="12" fill="url(#bgGrad)"/>\n};
    $o .= qq{<rect width="$w" height="$h" rx="12" fill="none" stroke="#ffffff" stroke-opacity="0.06" stroke-width="1.2"/>\n};
    $o .= header_row(title => "AI Usage Monitor", brand => "overview", color => $C{overview});

    my @custom_tabs = (
        { id => "overview",    dot => $C{overview} },
        { id => "spend",       dot => $C{spend} },
        { id => "sessions",    dot => $C{sessions} },
        { id => "claude",      brand => "claude" },
        { id => "antigravity", brand => "antigravity" },
        { id => "openai",      brand => "openai" },
        { id => "kiro",        brand => "kiro" },
    );
    $o .= tab_bar("overview", \@custom_tabs);

    # Overview Sub-Header matching OverviewTab.qml
    $o .= qq{<g transform="translate(16, 96)">\n};
    $o .= qq{  <text x="0" y="12" font-family="$UI" font-size="14" font-weight="700" fill="$C{text}">Overview</text>\n};
    $o .= qq{  <text x="368" y="12" text-anchor="end" font-family="$UI" font-size="10" fill="$C{muted}">7 providers</text>\n};
    $o .= qq{</g>\n};

    # Provider Rows
    my @rows = (
        { id => "claude",      name => "Claude",      accent => $C{claude},      pct => 61, detail => "Pro" },
        { id => "antigravity", name => "Antigravity", accent => $C{antigravity}, pct => 42, detail => "Google AI Pro" },
        { id => "openai",      name => "OpenAI",      accent => $C{openai},      pct => 20, detail => "Plus" },
        { id => "kiro",        name => "Kiro",        accent => $C{kiro},        pct => 75, detail => "Free" },
        { id => "grok",        name => "Grok",        accent => $C{grok},        pct => 35, detail => "Credits" },
        { id => "cursor",      name => "Cursor",      accent => $C{cursor},      pct => 58, detail => "Pro" },
        { id => "cline",       name => "Cline",       accent => $C{cline},       pct => 12, detail => "30d API" },
    );

    my $ry = 120;
    for my $r (@rows) {
        $o .= qq{<g transform="translate(16, $ry)">\n};
        $o .= qq{  <rect width="368" height="52" rx="8" fill="#ffffff" fill-opacity="0.04" stroke="#ffffff" stroke-opacity="0.08" stroke-width="1"/>\n};
        # Icon box
        $o .= qq{  <rect x="8" y="12" width="28" height="28" rx="6" fill="$r->{accent}" fill-opacity="0.15"/>\n};
        $o .= brand_glyph($r->{id}, 14, 18, 16, "", 1.0) . "\n";
        # Provider Name & Percentage
        $o .= qq{  <text x="44" y="22" font-family="$UI" font-size="12" font-weight="700" fill="$C{text}">$r->{name}</text>\n};
        $o .= qq{  <text x="360" y="22" text-anchor="end" font-family="$UI" font-size="12" font-weight="700" fill="$r->{accent}">$r->{pct}%</text>\n};
        # Progress Bar
        my $bar_w = int(316 * ($r->{pct} / 100));
        $o .= qq{  <rect x="44" y="28" width="316" height="6" rx="3" fill="#ffffff" fill-opacity="0.08"/>\n};
        $o .= qq{  <rect x="44" y="28" width="$bar_w" height="6" rx="3" fill="$r->{accent}"/>\n};
        # Detail line
        $o .= qq{  <text x="44" y="44" font-family="$UI" font-size="9.5" fill="$C{faint}">$r->{detail}</text>\n};
        $o .= qq{</g>\n};
        $ry += 58;
    }

    $o .= footer_row($w, 542, "", "12:31");
    $o .= qq{</svg>\n};
    write_svg('overview_tab.svg', $o);
    write_svg('general_tab.svg', $o);
}

# ── 9. SESSIONS_TAB.SVG (Sessions Tab) ───────────────────────────────────────
sub make_sessions_tab {
    my $w = 400; my $h = 474;
    my $o = qq{<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $w $h" width="$w" height="$h">\n};
    $o .= defs_block();
    $o .= qq{<rect width="$w" height="$h" rx="12" fill="url(#bgGrad)"/>\n};
    $o .= qq{<rect width="$w" height="$h" rx="12" fill="none" stroke="#ffffff" stroke-opacity="0.06" stroke-width="1.2"/>\n};
    $o .= header_row(title => "AI Usage Monitor", brand => "sessions", color => $C{sessions});

    my @custom_tabs = (
        { id => "overview",    dot => $C{overview} },
        { id => "spend",       dot => $C{spend} },
        { id => "sessions",    dot => $C{sessions} },
        { id => "claude",      brand => "claude" },
        { id => "antigravity", brand => "antigravity" },
        { id => "openai",      brand => "openai" },
        { id => "kiro",        brand => "kiro" },
    );
    $o .= tab_bar("sessions", \@custom_tabs);

    # Sub-header: Sessions + Count + Refresh button
    $o .= qq{<g transform="translate(16, 96)">\n};
    $o .= qq{  <text x="0" y="14" font-family="$UI" font-size="14" font-weight="700" fill="$C{text}">Sessions</text>\n};
    $o .= qq{  <text x="340" y="13" text-anchor="end" font-family="$UI" font-size="10" fill="$C{muted}">4 local sessions</text>\n};
    $o .= qq{  <g transform="translate(346, 0)">\n};
    $o .= qq{    <rect width="22" height="20" rx="4" fill="#ffffff" fill-opacity="0.04" stroke="#ffffff" stroke-opacity="0.08" stroke-width="1"/>\n};
    $o .= qq{    <path d="M14.65 3.35A6 6 0 1 0 17 8h-1.8a4.2 4.2 0 1 1-1.4-2.88L12 7h5V2l-2.35 2.35z" transform="scale(0.85) translate(3, 1)" fill="#9ca3af"/>\n};
    $o .= qq{  </g>\n};
    $o .= qq{</g>\n};

    # Search Bar (TextField)
    $o .= qq{<g transform="translate(16, 124)">\n};
    $o .= qq{  <rect width="368" height="26" rx="5" fill="#13141a" stroke="#ffffff" stroke-opacity="0.10" stroke-width="1"/>\n};
    $o .= qq{  <path d="M7 4a3 3 0 1 0 0 6 3 3 0 0 0 0-6zm-4.2 3a4.2 4.2 0 1 1 7.2 2.95l3.5 3.5-.85.85-3.5-3.5A4.2 4.2 0 0 1 2.8 7z" fill="$C{faint}" transform="translate(8, 5) scale(0.85)"/>\n};
    $o .= qq{  <text x="28" y="17" font-family="$UI" font-size="10" fill="$C{faint}">Search sessions…</text>\n};
    $o .= qq{</g>\n};

    # Sessions List
    my @sessions = (
        {
            accent    => $C{claude},
            title     => "Refactor audio pipeline for low latency",
            session   => "session-7b19a · Claude Code",
            detail    => "14 turns · 42.1k tokens · ~/projects/plasma/ai-usage",
            active    => 1,
            age       => "2m ago",
        },
        {
            accent    => $C{openai},
            title     => "Debug memory leak in websocket worker",
            session   => "session-c8201 · Codex CLI",
            detail    => "8 turns · 19.5k tokens · ~/projects/backend-service",
            active    => 0,
            age       => "45m ago",
        },
        {
            accent    => $C{grok},
            title     => "Generate mock fixtures for billing tests",
            session   => "session-94a20 · Grok CLI",
            detail    => "5 turns · 11.2k tokens · ~/projects/api-test-suite",
            active    => 0,
            age       => "2h ago",
        },
        {
            accent    => $C{cline},
            title     => "Update KDE Plasma 6 SVG vector assets",
            session   => "session-3f04b · Cline",
            detail    => "22 turns · 68.4k tokens · ~/projects/KDE-PLASMA",
            active    => 0,
            age       => "1d ago",
        },
    );

    my $sy = 158;
    for my $s (@sessions) {
        $o .= qq{<g transform="translate(16, $sy)">\n};
        $o .= qq{  <rect width="368" height="64" rx="8" fill="#ffffff" fill-opacity="0.04" stroke="#ffffff" stroke-opacity="0.08" stroke-width="1"/>\n};
        # Accent dot
        $o .= qq{  <circle cx="14" cy="18" r="4" fill="$s->{accent}"/>\n};
        # Title
        $o .= qq{  <text x="24" y="20" font-family="$UI" font-size="11.5" font-weight="700" fill="$C{text}">$s->{title}</text>\n};
        # Session Name
        $o .= qq{  <text x="24" y="35" font-family="$UI" font-size="9.5" fill="$C{dim}">$s->{session}</text>\n};
        # Detail (tokens/turns)
        $o .= qq{  <text x="24" y="50" font-family="$UI" font-size="9" fill="$C{faint}">$s->{detail}</text>\n};
        # State
        my $st_col = $s->{active} ? $s->{accent} : $C{muted};
        my $st_lbl = $s->{active} ? "Active" : "Idle";
        $o .= qq{  <text x="334" y="20" text-anchor="end" font-family="$UI" font-size="10.5" font-weight="700" fill="$st_col">$st_lbl</text>\n};
        # Age
        $o .= qq{  <text x="334" y="34" text-anchor="end" font-family="$UI" font-size="9.5" fill="$C{faint}">$s->{age}</text>\n};
        # Open in terminal button
        $o .= qq{  <g transform="translate(342, 12)">\n};
        $o .= qq{    <rect width="20" height="20" rx="4" fill="#ffffff" fill-opacity="0.04" stroke="#ffffff" stroke-opacity="0.08" stroke-width="1"/>\n};
        $o .= qq{    <path d="M3 3h5v1.5H4.5v7h7V9H13v4H3V3zm6 0h4v4h-1.5V4.6L8.5 7.6 7.4 6.5l3-3H9V3z" fill="#9ca3af" transform="scale(0.85) translate(4, 3)"/>\n};
        $o .= qq{  </g>\n};
        $o .= qq{</g>\n};
        $sy += 72;
    }

    $o .= footer_row($w, 456, "", "12:31");
    $o .= qq{</svg>\n};
    write_svg('sessions_tab.svg', $o);
    write_svg('session_tab.svg', $o);
}

# ── 10. SPEND_TAB.SVG (Cost Usage & Spend Tab) ──────────────────────────────
sub make_spend_tab {
    my $w = 400; my $h = 434;
    my $o = qq{<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $w $h" width="$w" height="$h">\n};
    $o .= defs_block();
    $o .= qq{<rect width="$w" height="$h" rx="12" fill="url(#bgGrad)"/>\n};
    $o .= qq{<rect width="$w" height="$h" rx="12" fill="none" stroke="#ffffff" stroke-opacity="0.06" stroke-width="1.2"/>\n};
    $o .= header_row(title => "AI Usage Monitor", brand => "spend", color => $C{spend});

    my @custom_tabs = (
        { id => "overview",    dot => $C{overview} },
        { id => "spend",       dot => $C{spend} },
        { id => "sessions",    dot => $C{sessions} },
        { id => "claude",      brand => "claude" },
        { id => "antigravity", brand => "antigravity" },
        { id => "openai",      brand => "openai" },
        { id => "kiro",        brand => "kiro" },
    );
    $o .= tab_bar("spend", \@custom_tabs);

    # Sub-header: Usage & Spend + Total
    $o .= qq{<g transform="translate(16, 96)">\n};
    $o .= qq{  <text x="0" y="14" font-family="$UI" font-size="14" font-weight="700" fill="$C{text}">Usage &amp; Spend</text>\n};
    $o .= qq{  <text x="368" y="14" text-anchor="end" font-family="$UI" font-size="13" font-weight="700" fill="$C{spend}">Σ \$48.35</text>\n};
    $o .= qq{</g>\n};

    # Note
    $o .= qq{<g transform="translate(16, 122)">\n};
    $o .= qq{  <text x="0" y="9" font-family="$UI" font-size="9" fill="$C{faint}">Totals come from each provider's own usage APIs and local CLI logs.</text>\n};
    $o .= qq{  <text x="0" y="21" font-family="$UI" font-size="9" fill="$C{faint}">Ranges differ (30-day, all-time, lifetime).</text>\n};
    $o .= qq{</g>\n};

    # Spend Rows
    my @spend_rows = (
        { name => "Claude",     accent => $C{claude},     note => "30d API",    cost => "\$24.15" },
        { name => "OpenAI",     accent => $C{openai},     note => "30d API",    cost => "\$12.80" },
        { name => "OpenRouter", accent => $C{openrouter}, note => "all-time",   cost => "\$6.40" },
        { name => "Mistral",    accent => $C{mistral},    note => "vibe CLI",   cost => "\$3.20" },
        { name => "Cursor",     accent => $C{cursor},     note => "on-demand",  cost => "\$1.80" },
    );

    my $cy = 156;
    for my $r (@spend_rows) {
        $o .= qq{<g transform="translate(16, $cy)">\n};
        $o .= qq{  <rect width="368" height="42" rx="8" fill="#ffffff" fill-opacity="0.04" stroke="#ffffff" stroke-opacity="0.08" stroke-width="1"/>\n};
        # Accent dot
        $o .= qq{  <circle cx="16" cy="21" r="4" fill="$r->{accent}"/>\n};
        # Name
        $o .= qq{  <text x="28" y="19" font-family="$UI" font-size="12" font-weight="700" fill="$C{text}">$r->{name}</text>\n};
        # Note
        $o .= qq{  <text x="28" y="33" font-family="$UI" font-size="9.5" fill="$C{faint}">$r->{note}</text>\n};
        # Cost
        $o .= qq{  <text x="354" y="26" text-anchor="end" font-family="$UI" font-size="12.5" font-weight="700" fill="$C{text}">$r->{cost}</text>\n};
        $o .= qq{</g>\n};
        $cy += 48;
    }

    $o .= footer_row($w, 416, "48.35", "12:31");
    $o .= qq{</svg>\n};
    write_svg('spend_tab.svg', $o);
    write_svg('cost_usage.svg', $o);
}

# ── Main ──────────────────────────────────────────────────────────────────────
make_claude_usage();
make_antigravity_usage();
make_openai_usage();
make_usage_chart();
make_settings();
make_claude_pill();
make_agy_pill();
make_overview_tab();
make_sessions_tab();
make_spend_tab();

print "All demo visuals generated successfully.\n";
