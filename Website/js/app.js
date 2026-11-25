/* AgentGauge website · native macOS 26 Tahoe interactive experience */
(function () {
  "use strict";

  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const I18N = window.AG_I18N;
  const ASSET_V = "1.2.4";
  const ICON = (id) => `assets/icons/${id}.png?v=${ASSET_V}`;

  /* ------------------------------------------------------------------ 29 authentic Coding-Plan & Foundation-Model vendors */
  const APPS = [
    ["codex", "ChatGPT / Codex", "c", "#3E8C79"], ["antigravity", "Antigravity", "c", "#5479B2"], ["claude", "Claude", "c", "#AD6E54"],
    ["cursor", "Cursor", "c", "#7165AD"], ["grokbot", "Grok Bot", "c", "#B37452"], ["windsurf", "Windsurf", "c", "#428E85"],
    ["workbuddy", "WorkBuddy", "c", "#498596"], ["trae", "Trae", "c", "#4C9468"], ["kiro", "Kiro", "c", "#7C62AD"],
    ["vscode", "VS Code (Copilot)", "c", "#4878A8"], ["qoder", "Qoder", "c", "#6368A8"], ["zed", "Zed", "c", "#4A6FA5"],
    ["warp", "Warp", "c", "#4A86A8"], ["devin", "Devin", "c", "#458C86"], ["intellij", "IntelliJ IDEA", "c", "#AD5F6E"],
    ["pycharm", "PyCharm", "c", "#4A9476"], ["webstorm", "WebStorm", "c", "#468996"],
    ["gemini", "Gemini", "a", "#597AB2"], ["grok", "Grok", "a", "#788494"], ["deepseek", "DeepSeek", "a", "#536DA8"],
    ["kimi", "Kimi", "a", "#6B7685"], ["chatglm", ["GLM", "智谱 GLM"], "a", "#4F6FB0"], ["qwen", ["Qwen", "通义千问 Qwen"], "a", "#6A64A8"],
    ["doubao", ["Doubao", "豆包"], "a", "#547EB0"], ["minimax", "MiniMax", "a", "#A8667A"], ["perplexity", "Perplexity", "a", "#3E7C87"],
    ["lechat", "Le Chat (Mistral)", "a", "#B57A4E"], ["manus", "Manus", "a", "#6B7685"], ["poe", "Poe", "a", "#7B66AD"],
  ];
  const TINT = Object.fromEntries(APPS.map((a) => [a[0], a[3]]));

  /* ------------------------------------------------------------------ 10 curated famous museum paintings (randomized) */
  const WALLPAPERS = [
    {
      src: "assets/wallpapers/monet-water-lilies.jpg",
      en: "Claude Monet · Water Lilies, c. 1915",
      zh: "克劳德·莫奈 · 睡莲, 约 1915",
    },
    {
      src: "assets/wallpapers/monet-antibes.jpg",
      en: "Claude Monet · Gardener’s House at Antibes, 1888",
      zh: "克劳德·莫奈 · 昂蒂布园丁小屋, 1888",
    },
    {
      src: "assets/wallpapers/monet-pourville.jpg",
      en: "Claude Monet · Low Tide at Pourville, 1882",
      zh: "克劳德·莫奈 · 普尔维尔退潮, 1882",
    },
    {
      src: "assets/wallpapers/vangogh-saint-remy.jpg",
      en: "Vincent van Gogh · Saint-Rémy Plane Trees, 1889",
      zh: "文森特·梵高 · 圣雷米的法国梧桐, 1889",
    },
    {
      src: "assets/wallpapers/hokusai-red-fuji.jpg",
      en: "Katsushika Hokusai · Fine Wind, Clear Morning, c. 1831",
      zh: "葛饰北斋 · 凯风快晴（赤富士）, 约 1831",
    },
    {
      src: "assets/wallpapers/turner-lucerne.jpg",
      en: "J. M. W. Turner · Lake of Lucerne, 1845",
      zh: "威廉·透纳 · 琉森湖晨雾, 1845",
    },
    {
      src: "assets/wallpapers/cezanne-victoire.jpg",
      en: "Paul Cézanne · Mont Sainte-Victoire, c. 1904",
      zh: "保罗·塞尚 · 圣维克多山, 约 1904",
    },
    {
      src: "assets/wallpapers/church-twilight.jpg",
      en: "Frederic Edwin Church · Twilight in the Wilderness, 1860",
      zh: "弗雷德里克·丘奇 · 荒野暮色, 1860",
    },
    {
      src: "assets/wallpapers/bierstadt-yosemite.jpg",
      en: "Albert Bierstadt · Yosemite Valley, 1866",
      zh: "阿尔伯特·比尔施塔特 · 优胜美地山谷, 1866",
    },
    {
      src: "assets/wallpapers/heade-point-judith.jpg",
      en: "Martin Johnson Heade · Point Judith, 1867",
      zh: "马丁·约翰逊·希德 · 朱迪思角夜海, 1867",
    },
  ];

  /* ------------------------------------------------------------------ synthetic demo snapshots (1:1 PromoDemoData.swift) */
  const DEMO = {
    antigravity: { level: 64, name: "Antigravity" },
    codex: { level: 82, name: "ChatGPT", working: true },
    cursor: { level: 68, name: "Cursor" },
    grokbot: { level: 69, name: "Grok Bot" },
    claude: { level: 83, name: "Claude" },
    workbuddy: { level: 52, name: "WorkBuddy", label: "3.2k" },
  };
  const LAB_APPS = ["grokbot", "cursor", "antigravity", "codex", "claude", "workbuddy"];
  const POPOVER_ORDER = ["antigravity", "cursor", "workbuddy", "deepseek", "grokbot", "gemini", "claude", "codex"];

  const SNAPSHOTS = {
    antigravity: {
      short: "Antigravity", title: "Antigravity", level: 64, reset: "4d 22h",
      badge: ["AI Ultra", "AI Ultra"],
      sub: ["hello@agentgauge.app · Google AI Ultra", "hello@agentgauge.app · Google AI Ultra"],
      windows: [
        [["Gemini 4 (Current)", "Gemini 4 (当前)"], 72, "1h 41m", true],
        [["Gemini · Weekly", "Gemini · 周限额"], 64, "4d 22h", true],
        [["Claude/GPT · Weekly", "Claude/GPT · 周限额"], 100, "6d 23h", true],
        [["Orchestrator", "Orchestrator"], 72, "1h 41m", false],
        [["Gemini 3.8 Flash", "Gemini 3.8 Flash"], 86, "1h 41m", false],
        [["Claude Opus 5.5", "Claude Opus 5.5"], 41, "4h 55m", false],
        [["Claude Sonnet 5.5", "Claude Sonnet 5.5"], 93, "4h 55m", false],
        [["GPT-OSS 120B", "GPT-OSS 120B"], 100, "4h 55m", false],
      ],
      note: ["500 credits available", "可用积分 500"],
    },
    cursor: {
      short: "Cursor", title: "Cursor", level: 68, reset: "5d 4h",
      badge: ["Ultra · 20x", "Ultra · 20x"],
      sub: ["code@agentgauge.app", "code@agentgauge.app"],
      windows: [
        [["Cursor Monthly (Primary)", "Cursor 月度额度 (主)"], 68, "5d 4h", true],
        [["Auto Model", "Auto 模型"], 88, "5d 4h", false],
        [["Claude Opus 5.5", "Claude Opus 5.5"], 46, "5d 4h", false],
        [["GPT-5.5 Codex", "GPT-5.5 Codex"], 74, "5d 4h", false],
      ],
      note: ["On-demand $0 / $200 cap", "按量计费 $0 / $200 上限"],
    },
    workbuddy: {
      short: "WorkBuddy", title: "WorkBuddy", level: 52, reset: "10d 11h",
      sidebarVal: "3.2k", heroVal: "3177/6068", credits: true,
      badge: ["Trial", "体验版"],
      sub: ["CodeBuddy Credits", "CodeBuddy 积分"],
      windows: [
        [["Credits Remaining", "剩余积分额度"], 52, "10d 11h", true, ["3177 pts", "3177 积分"]],
      ],
    },
    deepseek: {
      short: "DeepSeek", title: "DeepSeek", level: 48, reset: ["Pay-as-you-go", "按量计费"],
      sidebarVal: "¥29", heroVal: "¥28.50", credits: true,
      badge: ["API Balance", "API 余额"],
      sub: ["DeepSeek Balance API · Pay-as-you-go", "DeepSeek 官方 API · 按量计费"],
      windows: [
        [["Available API Balance", "DeepSeek API 可用余额"], 48, ["Pay-as-you-go", "按量计费"], true, ["¥28.50", "¥28.50"]],
      ],
      note: ["Direct local API key balance · Zero fake 100%", "本地 API Key 直连查询 · 真实可用余额"],
    },
    grokbot: {
      short: "Grok Bot", title: "Grok Bot", level: 69, reset: "5d 4h",
      badge: ["Premium", "Premium"],
      sub: ["grok@agentgauge.app", "grok@agentgauge.app"],
      windows: [
        [["Grok Weekly (Primary)", "Grok 周额度 (主)"], 69, "5d 4h", true],
        [["Auto / Flagship", "Auto / 主力模型"], 69, "5d 4h", false],
      ],
      note: ["31% of weekly plan used", "本周已使用 31% 的套餐额度"],
    },
    gemini: {
      short: "Gemini", title: "Gemini", level: 77, reset: "6h 10m", defaultPaused: true,
      badge: ["AI Ultra", "AI Ultra"],
      sub: ["hello@agentgauge.app · Google AI Ultra", "hello@agentgauge.app · Google AI Ultra"],
      windows: [
        [["Gemini Daily Quota", "Gemini App 每日额度"], 77, "6h 10m", true],
      ],
    },
    codex: {
      short: "Codex", title: "Codex", level: 82, reset: "3h 12m", working: true,
      badge: ["Pro Lite · 5x", "Pro Lite · 5x"],
      sub: ["dev@agentgauge.app", "dev@agentgauge.app"],
      windows: [
        [["5h Window (Primary)", "5 小时窗口 (主)"], 82, "3h 12m", true],
        [["Weekly Quota", "周额度"], 91, "5d 20h", true],
      ],
      note: ["Credits $128.90 · Reset voucher ×2", "Credits $128.90 · 满额重置券 ×2"],
    },
    claude: {
      short: "Claude", title: "Claude", level: 83, reset: "2h 18m",
      badge: ["Max 20x", "Max 20x"],
      sub: ["claude@agentgauge.app", "claude@agentgauge.app"],
      windows: [
        [["5h Session (Primary)", "5 小时会话 (主)"], 83, "2h 18m", true],
        [["Weekly · Opus", "周额度 · Opus"], 57, "3d 10h", true],
      ],
    },
  };

  /* ------------------------------------------------------------------ i18n (English primary by default) */
  let lang = "en";
  const safeGetStorage = (key) => {
    try { return window.localStorage.getItem(key); } catch (_) { return null; }
  };
  const safeSetStorage = (key, val) => {
    try { window.localStorage.setItem(key, val); } catch (_) {}
  };
  const pickLang = () => {
    const q = new URLSearchParams(location.search).get("lang");
    if (q === "zh" || q === "en") return q;
    const s = safeGetStorage("ag-lang-v2");
    if (s === "zh" || s === "en") return s;
    return "en";
  };
  const t = (k) => (I18N[lang] && I18N[lang][k] !== undefined ? I18N[lang][k] : I18N.en[k]);
  const bi = (v) => (Array.isArray(v) ? (lang === "zh" ? v[1] : v[0]) : v);
  const appName = bi;
  const langListeners = [];

  function applyLang(next, persist = false) {
    lang = next;
    document.documentElement.lang = lang === "zh" ? "zh-CN" : "en";
    $$("[data-i18n]").forEach((el) => {
      const v = t(el.dataset.i18n);
      if (typeof v === "string") el.innerHTML = v;
    });
    document.title = t("meta.title");
    const md = $('meta[name="description"]');
    if (md) md.setAttribute("content", t("meta.desc"));
    if (persist) safeSetStorage("ag-lang-v2", lang);
    langListeners.forEach((fn) => fn());
  }
  $$("[data-lang-toggle]").forEach((b) => b.addEventListener("click", () => applyLang(lang === "zh" ? "en" : "zh", true)));

  /* ------------------------------------------------------------------ color math (anodized mineral badge & bars) */
  function hexToHsl(hex) {
    const h = hex.replace("#", "");
    const r = parseInt(h.slice(0, 2), 16) / 255, g = parseInt(h.slice(2, 4), 16) / 255, b = parseInt(h.slice(4, 6), 16) / 255;
    const max = Math.max(r, g, b), min = Math.min(r, g, b);
    let hue = 0, sat = 0;
    const l = (max + min) / 2;
    if (max !== min) {
      const d = max - min;
      sat = l > 0.5 ? d / (2 - max - min) : d / (max + min);
      switch (max) {
        case r: hue = (g - b) / d + (g < b ? 6 : 0); break;
        case g: hue = (b - r) / d + 2; break;
        default: hue = (r - g) / d + 4;
      }
      hue *= 60;
    }
    return { h: Math.round(hue), s: Math.round(sat * 100), l: Math.round(l * 100) };
  }
  function mineralStyle(hex) {
    const { h, s } = hexToHsl(hex || "#587BA3");
    const ms = clamp(Math.round(s * 0.48), 18, 34);
    const ds = clamp(Math.round(s * 0.85), 36, 62);
    return `--ptb-top:hsla(${h},${ms}%,30%,0.92);--ptb-bot:hsla(${h},${ms}%,21%,0.95);--ptb-dot:hsl(${h},${ds}%,76%)`;
  }
  function barStyle(pct, hex) {
    if (pct <= 15) return `--bar-lo:#d9382e;--bar-hi:#ff453a`;
    if (pct <= 30) return `--bar-lo:#d98206;--bar-hi:#ff9f0a`;
    const { h, s, l } = hexToHsl(hex || "#587BA3");
    return `--bar-lo:hsl(${h},${clamp(s, 28, 56)}%,${clamp(l - 4, 38, 54)}%);--bar-hi:hsl(${h},${clamp(s + 6, 34, 66)}%,${clamp(l + 9, 50, 68)}%)`;
  }
  function pctClass(pct) { return pct <= 15 ? " low" : pct <= 30 ? " warn" : ""; }

  /* ------------------------------------------------------------------ reusable HoverTooltipCard renderer */
  function renderHoverCardHTML(id) {
    const s = SNAPSHOTS[id];
    if (!s) return "";
    const hex = TINT[id] || "#587BA3";
    const hero = s.heroVal || `${s.level}%`;
    const cdText = typeof s.reset === "string"
      ? (lang === "zh" ? `${s.reset} 重置` : `resets in ${s.reset}`)
      : bi(s.reset);
    const wins = s.windows || [];
    const multi = wins.length > 1;
    return `
      <div class="htc-head">
        <div class="mbp-hico">
          <img src="${ICON(id)}" alt="" draggable="false" />
          ${s.working ? '<span class="mbp-work"></span>' : ""}
        </div>
        <div class="mbp-hmeta">
          <div class="mbp-htitle">
            <b>${s.title}</b>
            ${s.badge ? `<span class="ptb" style="${mineralStyle(hex)}">${bi(s.badge)}</span>` : ""}
          </div>
          <div class="mbp-hsub">${bi(s.sub)}</div>
        </div>
        <div class="htc-right">
          <span class="htc-hero${s.credits ? " credits" : ""}${pctClass(s.level)}">${hero}</span>
          <span class="htc-cd${s.working ? " work" : ""}">${cdText}</span>
        </div>
      </div>
      ${multi ? `<div class="htc-rows">${wins.map(([lbl, pct, cd, pri, customVal]) => `
        <div class="htc-row${pri ? " pri" : ""}">
          <span class="htc-rlbl">${bi(lbl)}</span>
          <span class="htc-rbar" style="${barStyle(pct, hex)}"><i style="width:${clamp(pct, 4, 100)}%"></i></span>
          <span class="htc-rpct${pctClass(pct)}">${customVal ? bi(customVal) : `${pct}%`}</span>
          <span class="htc-rcd">${bi(cd)}</span>
        </div>`).join("")}</div>` : `<div class="htc-single" style="${barStyle(s.level, hex)}"><i style="width:${clamp(s.level, 5, 100)}%"></i></div>`}
      ${s.note ? `<div class="htc-sub" style="--sub-accent:${hex}"><i>✦</i><span>${bi(s.note)}</span></div>` : ""}
    `;
  }

  /* ------------------------------------------------------------------ reusable MenuBarPopoverView component */
  const ICON_REFRESH = `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.55"><path d="M13.2 8a5.2 5.2 0 11-1.5-3.7M13.2 2.8v2.9h-2.9" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
  const ICON_SLIDERS = `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M2.5 4.5h11M2.5 8h11M2.5 11.5h11"/><circle cx="5.5" cy="4.5" r="1.4" fill="#212228"/><circle cx="10.5" cy="8" r="1.4" fill="#212228"/><circle cx="6.8" cy="11.5" r="1.4" fill="#212228"/></svg>`;
  const ICON_POWER = `<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.55" stroke-linecap="round"><path d="M8 2.4v5.2M4.6 4.3a5.2 5.2 0 106.8 0"/></svg>`;

  function mountPopover(mountEl, opts = {}) {
    const state = {
      selected: opts.initial || "antigravity",
      running: true,
      paused: new Set(POPOVER_ORDER.filter((id) => SNAPSHOTS[id].defaultPaused)),
    };

    mountEl.innerHTML = `
      <div class="mbp${opts.staticSurface ? " mbp-static" : ""}">
        <div class="mbp-top">
          <div class="mbp-left">
            <div class="mbp-list">
              <div class="mbp-sel"></div>
              ${POPOVER_ORDER.map((id) => `
                <button type="button" class="mbp-row" data-mbp-row="${id}">
                  <span class="mbp-ico"><img src="${ICON(id)}" alt="" draggable="false" /><span class="mbp-work" hidden></span></span>
                  <span class="mbp-name"></span>
                  <span class="mbp-val"></span>
                </button>`).join("")}
            </div>
          </div>
          <div class="mbp-right">
            <div class="mbp-head">
              <div class="mbp-hico"><img src="" alt="" draggable="false" /><span class="mbp-work" hidden></span></div>
              <div class="mbp-hmeta">
                <div class="mbp-htitle"><b></b><span class="ptb"></span></div>
                <div class="mbp-hsub"></div>
              </div>
              <span class="mbp-hhero"></span>
              <button type="button" class="mbp-ibtn" data-mbp-refresh-one aria-label="Refresh">${ICON_REFRESH}</button>
            </div>
            <div class="mbp-div"></div>
            <div class="mbp-body"></div>
          </div>
        </div>
        <div class="mbp-foot">
          <button type="button" class="mbp-cbtn" data-mbp-toggle><span class="mbp-sdot"></span><span data-mbp-runlbl></span></button>
          <button type="button" class="mbp-cbtn" data-mbp-refresh-all>${ICON_REFRESH}<span data-mbp-reflbl></span></button>
          <span class="mbp-spacer"></span>
          <button type="button" class="mbp-cbtn" data-mbp-settings>${ICON_SLIDERS}<span data-mbp-setlbl></span></button>
          <button type="button" class="mbp-ibtn" data-mbp-power aria-label="Close">${ICON_POWER}</button>
        </div>
      </div>`;

    const root = $(".mbp", mountEl);
    const selEl = $(".mbp-sel", root);
    const rows = $$(".mbp-row", root);
    const bodyEl = $(".mbp-body", root);

    function syncSidebar() {
      const idx = Math.max(0, POPOVER_ORDER.indexOf(state.selected));
      const selHex = TINT[state.selected] || "#5479B2";
      selEl.style.transform = `translate3d(0, ${idx * 36}px, 0)`;
      selEl.style.setProperty("--row-accent", selHex);

      rows.forEach((row) => {
        const id = row.dataset.mbpRow;
        const s = SNAPSHOTS[id];
        const isPaused = !state.running || state.paused.has(id);
        const isSel = id === state.selected;
        row.classList.toggle("on", isSel);
        row.classList.toggle("paused", isPaused);
        $(".mbp-name", row).textContent = s.short;
        $(".mbp-work", row).hidden = isPaused || !s.working;
        const valEl = $(".mbp-val", row);
        if (isPaused) {
          valEl.className = "mbp-val pause-tag";
          valEl.textContent = lang === "zh" ? "暂停" : "Paused";
        } else {
          valEl.className = `mbp-val${pctClass(s.level)}`;
          valEl.textContent = s.sidebarVal || `${s.level}%`;
        }
      });
    }

    function syncDetail(animateBars = false) {
      const id = state.selected;
      const s = SNAPSHOTS[id];
      const hex = TINT[id] || "#5479B2";
      const isPaused = !state.running || state.paused.has(id);

      const hImg = $(".mbp-hico img", root);
      hImg.src = ICON(id);
      hImg.style.opacity = isPaused ? "0.5" : "1";
      $(".mbp-hico .mbp-work", root).hidden = isPaused || !s.working;
      $(".mbp-htitle b", root).textContent = s.title;
      const ptb = $(".mbp-htitle .ptb", root);
      ptb.textContent = bi(s.badge);
      ptb.setAttribute("style", mineralStyle(hex));
      $(".mbp-hsub", root).textContent = bi(s.sub);

      const heroEl = $(".mbp-hhero", root);
      if (isPaused) {
        heroEl.className = "mbp-hhero";
        heroEl.style.color = "rgba(255,255,255,0.38)";
        heroEl.textContent = "—";
      } else {
        heroEl.style.color = "";
        heroEl.className = `mbp-hhero${s.credits ? " credits" : ""}${pctClass(s.level)}`;
        heroEl.textContent = s.heroVal || `${s.level}%`;
      }

      if (isPaused) {
        const msg = !state.running
          ? (lang === "zh" ? "全局监控已暂停" : "Monitoring is paused")
          : (lang === "zh" ? `${s.short} 当前已暂停监控` : `${s.short} monitoring is paused`);
        const btnTxt = lang === "zh" ? "恢复监控" : "Resume monitoring";
        bodyEl.innerHTML = `
          <div class="mbp-empty">
            <div>${msg}</div>
            <button type="button" class="mbp-cbtn accent" data-mbp-resume>${btnTxt}</button>
          </div>`;
        $("[data-mbp-resume]", bodyEl).addEventListener("click", () => {
          if (opts.onInteract) opts.onInteract();
          state.running = true;
          state.paused.delete(id);
          render(true);
        });
      } else {
        const wins = s.windows || [];
        bodyEl.innerHTML = wins.map(([lbl, pct, cd, pri, customVal]) => `
          <div class="mbp-mrow${pri ? " pri" : ""}">
            <div class="mbp-mline">
              <span class="mbp-mlbl">${bi(lbl)}</span>
              <span class="mbp-mpct${pctClass(pct)}">${customVal ? bi(customVal) : `${pct}%`}</span>
              <span class="mbp-mcd">${bi(cd)}</span>
            </div>
            <div class="mbp-bar" style="${barStyle(pct, hex)}"><i style="width:${animateBars ? 6 : clamp(pct, 4, 100)}%" data-target-w="${clamp(pct, 4, 100)}"></i></div>
          </div>`).join("") + (s.note ? `<div class="mbp-sub" style="--sub-accent:${hex}"><i>✦</i><span>${bi(s.note)}</span></div>` : "");

        if (animateBars) {
          requestAnimationFrame(() => requestAnimationFrame(() => {
            $$("[data-target-w]", bodyEl).forEach((b) => { b.style.width = `${b.dataset.targetW}%`; });
          }));
        }
      }
    }

    function syncFooter() {
      $(".mbp-sdot", root).classList.toggle("off", !state.running);
      $("[data-mbp-runlbl]", root).textContent = state.running
        ? (lang === "zh" ? "运行中" : "Running")
        : (lang === "zh" ? "已暂停" : "Paused");
      $("[data-mbp-reflbl]", root).textContent = lang === "zh" ? "刷新" : "Refresh";
      $("[data-mbp-setlbl]", root).textContent = lang === "zh" ? "设置" : "Settings";
    }

    function render(animateBars = false) {
      syncSidebar();
      syncDetail(animateBars);
      syncFooter();
    }

    function select(id, fromUser = false) {
      if (!SNAPSHOTS[id] || state.selected === id) return;
      if (fromUser && opts.onInteract) opts.onInteract();
      state.selected = id;
      syncSidebar();
      syncDetail(false);
    }

    rows.forEach((row) => {
      const id = row.dataset.mbpRow;
      row.addEventListener("pointerenter", () => select(id, true));
      row.addEventListener("click", () => select(id, true));
    });

    // Smooth wheel scrolling inside model body without hijacking page scroll unnecessarily
    bodyEl.addEventListener("wheel", (e) => {
      if (bodyEl.scrollHeight > bodyEl.clientHeight) e.stopPropagation();
    }, { passive: true });

    function spinAndPulse(btn) {
      if (opts.onInteract) opts.onInteract();
      btn.classList.remove("spin-once");
      void btn.offsetWidth;
      btn.classList.add("spin-once");
      syncDetail(true);
    }

    $("[data-mbp-refresh-one]", root).addEventListener("click", (e) => spinAndPulse(e.currentTarget));
    $("[data-mbp-refresh-all]", root).addEventListener("click", (e) => spinAndPulse(e.currentTarget));
    $("[data-mbp-toggle]", root).addEventListener("click", () => {
      if (opts.onInteract) opts.onInteract();
      state.running = !state.running;
      render(state.running);
    });
    $("[data-mbp-settings]", root).addEventListener("click", () => {
      if (opts.onInteract) opts.onInteract();
      const sc = $("#settingsCard");
      if (sc) {
        sc.scrollIntoView({ behavior: "smooth", block: "center" });
        const art = $("#bentoWinArt");
        if (art) { art.classList.add("focus-settings"); setTimeout(() => art.classList.remove("focus-settings"), 2200); }
      }
    });
    $("[data-mbp-power]", root).addEventListener("click", () => {
      if (opts.onInteract) opts.onInteract();
      if (opts.onClose) opts.onClose();
      else { state.running = !state.running; render(state.running); }
    });

    langListeners.push(() => render(false));
    render(false);

    return {
      select,
      getSelected: () => state.selected,
      wakeAndSelect: (id) => {
        if (!SNAPSHOTS[id]) return;
        state.running = true;
        state.paused.delete(id);
        state.selected = id;
        render(false);
      },
    };
  }

  /* ------------------------------------------------------------------ toast + download */
  const toastEl = $("#toast");
  let toastTimer;
  function toast(msg) {
    toastEl.textContent = msg;
    toastEl.classList.add("on");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toastEl.classList.remove("on"), 2600);
  }
  $$("[data-repo]").forEach((a) => {
    const cfg = window.AG_CONFIG || {};
    if (cfg.repoUrl) a.href = cfg.repoUrl;
  });
  $$("[data-download]").forEach((a) => {
    const cfg = window.AG_CONFIG || {};
    if (cfg.downloadUrl) {
      a.href = cfg.downloadUrl;
      if (cfg.fileName) a.setAttribute("download", cfg.fileName);
      return;
    }
    a.addEventListener("click", (e) => {
      if (a.closest("#download")) { e.preventDefault(); toast(t("toast.soon")); }
    });
  });

  /* ------------------------------------------------------------------ nav */
  const nav = $("#nav");
  function onScroll() { nav.classList.toggle("scrolled", window.scrollY > 12); }
  window.addEventListener("scroll", onScroll, { passive: true });

  /* ------------------------------------------------------------------ reveal */
  const io = new IntersectionObserver((entries) => {
    entries.forEach((e) => { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } });
  }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
  function observeReveals(root = document) {
    $$(".reveal:not(.in)", root).forEach((el) => {
      const sibs = $$(":scope > .reveal", el.parentElement);
      el.style.setProperty("--d", `${Math.min(sibs.indexOf(el), 6) * 0.08}s`);
      io.observe(el);
    });
  }
  function watchVisible(el, cb) {
    const o = new IntersectionObserver((es) => es.forEach((e) => cb(e.isIntersecting)), { threshold: 0.01 });
    o.observe(el);
  }

  /* ------------------------------------------------------------------ image loading */
  const imgCache = new Map();
  function loadImg(src) {
    if (!imgCache.has(src)) {
      imgCache.set(src, new Promise((res, rej) => { const i = new Image(); i.decoding = "async"; i.onload = () => res(i); i.onerror = rej; i.src = src; }));
    }
    return imgCache.get(src);
  }

  /* ================================================================== HERO STAGE */
  const stage = $("#stage");
  const inner = $("#stageInner");
  const pop = $("#pop");
  const isCompactStage = () => window.matchMedia("(max-width: 720px), (hover: none)").matches;
  const stageLogicalW = () => inner.offsetWidth || 1240;
  let stageScale = 1, activeDock = null, hideTipTimer = 0;
  function fitStage() {
    const lw = stageLogicalW();
    stageScale = (stage.clientWidth || lw) / lw;
    inner.style.transform = `scale(${stageScale})`;
    if (pop.classList.contains("open")) placePop();
    if (activeDock) positionDockOverlay(activeDock);
  }
  new ResizeObserver(fitStage).observe(stage);

  // Curated 10 classical paintings: shuffled random deck + smooth crossfade
  const wallEls = [$("#wallA"), $("#wallB")];
  const wallPlaque = $("#wallPlaque");
  const wallMeta = $("#wallMeta");
  let wallDeck = [], wallPos = 0, wallLayer = 0;

  function makeShuffledDeck(avoidFirst = -1) {
    const arr = WALLPAPERS.map((_, i) => i);
    for (let i = arr.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [arr[i], arr[j]] = [arr[j], arr[i]];
    }
    if (arr[0] === avoidFirst && arr.length > 1) [arr[0], arr[1]] = [arr[1], arr[0]];
    return arr;
  }
  wallDeck = makeShuffledDeck();
  let wallIdx = wallDeck[0];
  wallEls[0].src = WALLPAPERS[wallIdx].src;
  wallEls[1].src = WALLPAPERS[wallDeck[1 % wallDeck.length]].src;

  function syncWallMeta() {
    const w = WALLPAPERS[wallIdx];
    wallMeta.textContent = lang === "zh" ? w.zh : w.en;
  }
  async function nextRandomWallpaper(spinBtn = false) {
    wallPos++;
    if (wallPos >= wallDeck.length) {
      wallDeck = makeShuffledDeck(wallIdx);
      wallPos = 0;
    }
    const target = wallDeck[wallPos];
    if (spinBtn) {
      wallPlaque.classList.remove("spin");
      void wallPlaque.offsetWidth;
      wallPlaque.classList.add("spin");
    }
    try { await loadImg(WALLPAPERS[target].src); } catch (_) { return; }
    wallIdx = target;
    const nextLayer = 1 - wallLayer;
    wallEls[nextLayer].src = WALLPAPERS[wallIdx].src;
    wallEls[nextLayer].classList.add("on");
    wallEls[wallLayer].classList.remove("on");
    wallLayer = nextLayer;
    syncWallMeta();
  }
  wallPlaque.addEventListener("click", (e) => {
    e.stopPropagation();
    nextRandomWallpaper(true);
  });
  langListeners.push(syncWallMeta);

  // Menu bar labels + clock
  function renderMenubar() {
    $("#mbFinder").textContent = t("mb.finder");
    $("#mbMenus").innerHTML = t("mb.menus").map((m) => `<span>${m}</span>`).join("");
    const d = new Date();
    const hm = `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
    const wk = lang === "zh" ? ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][d.getDay()] : d.toLocaleDateString("en-US", { weekday: "short" });
    $("#mbClock").textContent = `${wk} ${hm}`;
  }
  langListeners.push(renderMenubar);
  setInterval(renderMenubar, 30000);

  // Dock + live gliding HoverTooltipCard
  const DOCK = ["finder", "safari", "antigravity", "codex", "cursor", "grokbot", "claude", "workbuddy", "|", "settings"];
  const SYS_LABEL = { finder: ["Finder", "访达"], safari: ["Safari", "Safari 浏览器"], settings: ["System Settings", "系统设置"] };
  const dockEl = $("#dock");
  const liveTip = $("#liveTip");
  const labelEl = $("#dockLabel");
  const dockTiles = {};
  const dockItemEls = [];

  DOCK.forEach((id) => {
    if (id === "|") { const s = document.createElement("div"); s.className = "dock-sep"; dockEl.appendChild(s); return; }
    const item = document.createElement("div");
    item.className = "dock-item";
    item.dataset.id = id;
    if (!DEMO[id]) item.dataset.sys = "1";
    item.innerHTML = `<img src="${ICON(id)}" alt="" draggable="false" />`;
    if (DEMO[id]) {
      const c = document.createElement("canvas");
      c.width = c.height = 256;
      item.appendChild(c);
      dockTiles[id] = { item, canvas: c, ctx: c.getContext("2d"), motion: null };
    }
    dockEl.appendChild(item);
    dockItemEls.push(item);
  });

  const toStage = (el) => {
    const r = el.getBoundingClientRect(), s = inner.getBoundingClientRect();
    return { x: (r.left - s.left) / stageScale, y: (r.top - s.top) / stageScale, w: r.width / stageScale, h: r.height / stageScale };
  };

  function positionDockOverlay(id) {
    const item = dockEl.querySelector(`[data-id="${id}"]`);
    if (!item || !item.offsetWidth) {
      setDockActive(null);
      updateDockMagnification(null);
      return false;
    }
    const b = toStage(item);
    const cx = b.x + b.w / 2;
    labelEl.style.setProperty("--lx", `${cx}px`);
    if (SNAPSHOTS[id]) {
      const w = liveTip.offsetWidth || 320;
      const tx = Math.round(clamp(cx - w / 2, 10, stageLogicalW() - w - 10));
      liveTip.style.setProperty("--tx", `${tx}px`);
    }
    return true;
  }

  function setDockActive(id) {
    clearTimeout(hideTipTimer);
    if (activeDock === id) return;
    if (id) {
      const checkItem = dockEl.querySelector(`[data-id="${id}"]`);
      if (!checkItem || !checkItem.offsetWidth) id = null;
    }
    activeDock = id;
    Object.entries(dockTiles).forEach(([k, d]) => {
      if (d.motion) d.motion.target = k === id ? 1 : 0;
    });
    if (!id) {
      labelEl.classList.remove("on");
      hideTipTimer = setTimeout(() => {
        liveTip.classList.remove("on");
        liveTip.setAttribute("aria-hidden", "true");
      }, 80);
      ensureLoop();
      return;
    }
    const name = DEMO[id] ? DEMO[id].name : appName(SYS_LABEL[id] || id);
    labelEl.textContent = name;
    labelEl.classList.add("on");

    if (SNAPSHOTS[id]) {
      liveTip.innerHTML = renderHoverCardHTML(id);
      positionDockOverlay(id);
      liveTip.classList.add("on");
      liveTip.setAttribute("aria-hidden", "false");
      const d = dockTiles[id];
      if (d && d.motion) d.motion.kick((Math.random() > 0.5 ? 1 : -1) * 0.65);
    } else {
      positionDockOverlay(id);
      liveTip.classList.remove("on");
      liveTip.setAttribute("aria-hidden", "true");
    }
    ensureLoop();
  }
  langListeners.push(() => {
    if (activeDock) {
      const name = DEMO[activeDock] ? DEMO[activeDock].name : appName(SYS_LABEL[activeDock] || activeDock);
      labelEl.textContent = name;
      if (SNAPSHOTS[activeDock]) liveTip.innerHTML = renderHoverCardHTML(activeDock);
      positionDockOverlay(activeDock);
    }
  });

  function updateDockMagnification(stageX) {
    dockItemEls.forEach((item) => {
      if (!item.offsetWidth || stageX === null) {
        item.style.setProperty("--ms", "1");
        item.style.setProperty("--dy", "0px");
        return;
      }
      const b = toStage(item);
      const dist = Math.abs(stageX - (b.x + b.w / 2));
      const g = Math.exp(-(dist * dist) / (2 * 50 * 50));
      const scale = 1 + 0.18 * g;
      const dy = -11 * g;
      item.style.setProperty("--ms", scale.toFixed(3));
      item.style.setProperty("--dy", `${dy.toFixed(1)}px`);
    });
  }

  function focusDockItem(id) {
    const item = dockEl.querySelector(`[data-id="${id}"]`);
    if (!item || !item.offsetWidth) return;
    const b = toStage(item);
    updateDockMagnification(b.x + b.w / 2);
    setDockActive(id);
  }

  // Hero Stage Menu Bar Popover (seamless single-contour macOS NSPopover geometry)
  const popGlass = $("#popGlass");
  const popRimPath = $("#popRimPath");
  const gauge = $("#mbGauge");
  let lastTouch = -1e9;
  function userTouched() { lastTouch = performance.now(); }

  function popoverContourPath(cx) {
    const c = clamp(Math.round(cx * 2) / 2, 38, 410);
    return `M 20 12 L ${(c - 15).toFixed(1)} 12 C ${(c - 9).toFixed(1)} 12 ${(c - 4.8).toFixed(1)} 1.5 ${c.toFixed(1)} 1.5 C ${(c + 4.8).toFixed(1)} 1.5 ${(c + 9).toFixed(1)} 12 ${(c + 15).toFixed(1)} 12 L 428 12 A 20 20 0 0 1 448 32 L 448 336 A 20 20 0 0 1 428 356 L 20 356 A 20 20 0 0 1 0 336 L 0 32 A 20 20 0 0 1 20 12 Z`;
  }

  function placePop() {
    const g = toStage(gauge);
    const left = clamp(g.x + g.w / 2 - 224, 8, stageLogicalW() - 448 - 8);
    const cx = g.x + g.w / 2 - left;
    pop.style.left = `${left}px`;
    pop.style.setProperty("--pop-ox", `${((cx / 448) * 100).toFixed(1)}%`);
    const d = popoverContourPath(cx);
    popGlass.style.clipPath = `path("${d}")`;
    popGlass.style.webkitClipPath = `path("${d}")`;
    popRimPath.setAttribute("d", d);
  }
  function setPop(open) {
    if (open && isCompactStage()) {
      setDockActive(null);
      updateDockMagnification(null);
    }
    placePop();
    pop.classList.toggle("open", open);
    gauge.classList.toggle("on", open);
    pop.setAttribute("aria-hidden", String(!open));
  }

  const stagePopover = mountPopover($("#stagePopMount"), {
    initial: "antigravity",
    onInteract: userTouched,
    onClose: () => setPop(false),
  });

  let gaugeHoverTimer = 0;
  gauge.addEventListener("pointerenter", (e) => {
    if (e.pointerType === "touch") return;
    userTouched();
    clearTimeout(gaugeHoverTimer);
    if (!pop.classList.contains("open")) {
      gaugeHoverTimer = setTimeout(() => setPop(true), 110);
    }
  });
  gauge.addEventListener("pointerleave", () => clearTimeout(gaugeHoverTimer));
  gauge.addEventListener("click", (e) => {
    e.stopPropagation();
    userTouched();
    clearTimeout(gaugeHoverTimer);
    setPop(!pop.classList.contains("open"));
  });

  // Clicking desktop wallpaper dismisses popover / active mobile Dock card just like macOS NSPopover (.transient)
  inner.addEventListener("click", (e) => {
    if (e.target.closest("#pop, #mbGauge, #dock, #wallPlaque")) return;
    if (pop.classList.contains("open")) {
      userTouched();
      setPop(false);
    } else if (activeDock) {
      userTouched();
      updateDockMagnification(null);
      setDockActive(null);
    }
  });

  // Pointer & Touch → Dock
  let lastPX = null, lastDockTouch = false;
  function hitTestDock(stageX) {
    let closestId = null, bestDist = 46;
    dockItemEls.forEach((it) => {
      if (!it.offsetWidth) return;
      const b = toStage(it);
      const bonus = it.dataset.id === activeDock ? 5.5 : 0;
      const d = Math.abs(stageX - (b.x + b.w / 2)) - bonus;
      if (d < bestDist) { bestDist = d; closestId = it.dataset.id; }
    });
    return closestId;
  }

  dockEl.addEventListener("pointerdown", (e) => {
    lastDockTouch = e.pointerType === "touch";
    if (e.pointerType !== "touch") return;
    userTouched();
    if (pop.classList.contains("open")) setPop(false);
    const sRect = inner.getBoundingClientRect();
    const stageX = (e.clientX - sRect.left) / stageScale;
    const item = e.target.closest(".dock-item");
    const id = (item && item.offsetWidth ? item.dataset.id : null) || hitTestDock(stageX);
    if (id) {
      const targetEl = dockEl.querySelector(`[data-id="${id}"]`);
      const b = targetEl ? toStage(targetEl) : { x: stageX, w: 0 };
      updateDockMagnification(b.x + b.w / 2);
      const wasActive = activeDock === id;
      setDockActive(id);
      if (wasActive && dockTiles[id] && dockTiles[id].motion) {
        dockTiles[id].motion.kick((Math.random() > 0.5 ? 1 : -1) * 0.75);
        ensureLoop();
      }
    }
    lastPX = e.clientX;
  });

  dockEl.addEventListener("pointermove", (e) => {
    userTouched();
    if (e.pointerType === "touch" && pop.classList.contains("open")) setPop(false);
    const sRect = inner.getBoundingClientRect();
    const stageX = (e.clientX - sRect.left) / stageScale;
    updateDockMagnification(stageX);

    const closestId = hitTestDock(stageX);
    if (e.pointerType !== "touch" || closestId) setDockActive(closestId);

    if (lastPX !== null && activeDock && dockTiles[activeDock] && dockTiles[activeDock].motion) {
      dockTiles[activeDock].motion.kick(clamp((e.clientX - lastPX) * 0.014, -0.55, 0.55));
    }
    lastPX = e.clientX;
  });
  dockEl.addEventListener("pointerleave", (e) => {
    lastPX = null;
    if (e.pointerType === "touch") return;
    updateDockMagnification(null);
    setDockActive(null);
  });
  dockEl.addEventListener("pointercancel", () => { lastPX = null; });
  dockEl.addEventListener("click", (e) => {
    const item = e.target.closest(".dock-item");
    if (!item || !item.offsetWidth) return;
    userTouched();
    const id = item.dataset.id;
    if (dockTiles[id] && dockTiles[id].motion) dockTiles[id].motion.kick(0.95);
    if (lastDockTouch || isCompactStage()) {
      if (pop.classList.contains("open")) setPop(false);
      focusDockItem(id);
      if (POPOVER_ORDER.includes(id)) stagePopover.wakeAndSelect(id);
      ensureLoop();
      return;
    }
    if (POPOVER_ORDER.includes(id)) {
      stagePopover.wakeAndSelect(id);
      if (!pop.classList.contains("open")) setPop(true);
    } else if (id === "settings") {
      const sc = $("#settingsCard");
      if (sc) sc.scrollIntoView({ behavior: "smooth", block: "center" });
    }
  });

  // Gentle idle showcase (yields immediately when visitor interacts)
  const POP_TOUR = ["antigravity", "cursor", "workbuddy", "grokbot", "codex"];
  const DOCK_TOUR = ["codex", "antigravity", "cursor", "grokbot", "claude", "workbuddy"];
  let popI = 0, dockI = 0, stageVisible = false;
  setTimeout(() => {
    if (isCompactStage()) focusDockItem(DOCK_TOUR[0]);
    else setPop(true);
  }, reduceMotion ? 0 : 650);
  setInterval(() => {
    if (!stageVisible || reduceMotion || performance.now() - lastTouch < 8000) return;
    if (isCompactStage() && !pop.classList.contains("open")) {
      focusDockItem(DOCK_TOUR[++dockI % DOCK_TOUR.length]);
    } else if (pop.classList.contains("open")) {
      stagePopover.select(POP_TOUR[++popI % POP_TOUR.length], false);
    }
  }, 3400);
  setInterval(() => {
    if (!stageVisible || reduceMotion || document.hidden) return;
    nextRandomWallpaper(false);
  }, 15000);
  watchVisible(stage, (v) => { stageVisible = v; if (v) ensureLoop(); });

  /* ================================================================== BENTO INTERACTIVE CARDS */
  // Card 1: Interactive Hover Card + Mini Dock switcher
  const BENTO_HOVER_APPS = ["antigravity", "cursor", "codex", "grokbot", "claude"];
  const bentoTip = $("#bentoTip");
  const bentoMiniDock = $("#bentoMiniDock");
  let bentoHoverId = "antigravity";

  bentoMiniDock.innerHTML = `<span class="mini-dock-sel" id="bentoMiniSel"></span>` +
    BENTO_HOVER_APPS.map((id) => `<button type="button" data-bento-app="${id}" role="tab" aria-label="${SNAPSHOTS[id].title}"><img src="${ICON(id)}" alt="" draggable="false" /></button>`).join("");
  const bentoMiniSel = $("#bentoMiniSel");

  function syncBentoMiniSel() {
    const btn = $(`[data-bento-app="${bentoHoverId}"]`, bentoMiniDock);
    const idx = Math.max(0, BENTO_HOVER_APPS.indexOf(bentoHoverId));
    const x = btn && btn.offsetWidth ? (btn.offsetLeft - bentoMiniSel.offsetLeft) : idx * 50;
    bentoMiniSel.style.transform = `translate3d(${x}px, 0, 0)`;
  }

  function setBentoHover(id, anim = false) {
    if (!SNAPSHOTS[id]) return;
    const changed = bentoHoverId !== id;
    bentoHoverId = id;
    syncBentoMiniSel();
    bentoTip.innerHTML = renderHoverCardHTML(id);
    if (anim && changed && !reduceMotion) {
      bentoTip.classList.remove("swap");
      void bentoTip.offsetWidth;
      bentoTip.classList.add("swap");
    }
  }
  $$("[data-bento-app]", bentoMiniDock).forEach((btn) => {
    btn.addEventListener("pointerenter", (e) => { if (e.pointerType !== "touch") setBentoHover(btn.dataset.bentoApp, true); });
    btn.addEventListener("click", () => setBentoHover(btn.dataset.bentoApp, true));
  });
  new ResizeObserver(syncBentoMiniSel).observe(bentoMiniDock);
  langListeners.push(() => setBentoHover(bentoHoverId));
  setBentoHover("antigravity");

  // Card 2: Full interactive MenuBarPopoverView inside Bento
  mountPopover($("#bentoPopMount"), { staticSurface: true, initial: "cursor" });
  const bentoPopArt = $("#bentoPopArt");
  const bentoPopScale = $("#bentoPopScale");
  function fitBentoPop() {
    const availW = (bentoPopArt.clientWidth || 520) - 16;
    const availH = (bentoPopArt.clientHeight || 400) - 16;
    const sc = Math.min(1, availW / 448, availH / 344);
    bentoPopScale.style.transform = `translate(-50%, -50%) scale(${sc.toFixed(3)})`;
  }
  new ResizeObserver(fitBentoPop).observe(bentoPopArt);

  // Card 4: Settings & Studio interactive window focus
  const bentoWinArt = $("#bentoWinArt");
  const shotSettings = $(".shot-settings", bentoWinArt);
  const shotStudio = $(".shot-studio", bentoWinArt);
  shotSettings.addEventListener("pointerenter", () => { bentoWinArt.classList.add("focus-settings"); bentoWinArt.classList.remove("focus-studio"); });
  shotStudio.addEventListener("pointerenter", () => { bentoWinArt.classList.add("focus-studio"); bentoWinArt.classList.remove("focus-settings"); });
  bentoWinArt.addEventListener("pointerleave", () => { bentoWinArt.classList.remove("focus-settings", "focus-studio"); });
  shotSettings.addEventListener("click", () => { bentoWinArt.classList.toggle("focus-settings"); bentoWinArt.classList.remove("focus-studio"); });
  shotStudio.addEventListener("click", () => { bentoWinArt.classList.toggle("focus-studio"); bentoWinArt.classList.remove("focus-settings"); });

  /* ================================================================== LIQUID (1024px Lab + 512px Dock/Dodge) */
  let dockRenderer = null, labRenderer = null;
  const lab = {
    id: "grokbot", level: 69, target: 69, style: "split", motion: null, tween: null, visible: false,
    px: null, pdx: 0, lastAuto: 0, canvas: $("#labCanvas"),
  };
  const dodge = { canvas: $("#dodgeCanvas"), art: $("#dodgeArt"), visible: false, motion: null, t: 0, manualLevel: null };
  const dodgeCtx = dodge.canvas.getContext("2d");

  async function initLiquid() {
    try {
      await Promise.race([
        Promise.all([document.fonts.load('700 64px "Cabinet Grotesk"'), document.fonts.load('500 16px "Cabinet Grotesk"')]),
        new Promise((r) => setTimeout(r, 1500)),
      ]);
      const off = document.createElement("canvas");
      dockRenderer = new AGLiquid.LiquidRenderer(off, 512);
      const labSide = window.innerWidth <= 720 ? 512 : 1024;
      labRenderer = new AGLiquid.LiquidRenderer(lab.canvas, labSide);

      const ids = Object.keys(DEMO);
      const imgs = await Promise.all(ids.map((id) => loadImg(ICON(id))));
      ids.forEach((id, i) => { dockRenderer.addIcon(id, imgs[i]); labRenderer.addIcon(id, imgs[i]); });
      Object.entries(dockTiles).forEach(([id, d], i) => { d.motion = new AGLiquid.TileMotion(i * 1.3 + 0.4); });
      lab.motion = new AGLiquid.TileMotion(0.4);
      lab.motion.target = 1;
      dodge.motion = new AGLiquid.TileMotion(2.2);
      dodge.motion.target = 1;
      if (activeDock && dockTiles[activeDock]) dockTiles[activeDock].motion.target = 1;
      if (reduceMotion) {
        lab.motion.hover = 1; dodge.motion.hover = 1;
        drawLab(); drawDodge();
      }
      ensureLoop();
    } catch (err) {
      console.warn("[AgentGauge] WebGL unavailable, falling back to static icons.", err);
      const fb = $("#labFallback");
      fb.src = ICON(lab.id); fb.hidden = false; lab.canvas.hidden = true;
    }
  }

  function drawDockTile(id, d) {
    const m = d.motion;
    const demo = DEMO[id];
    dockRenderer.render({ id, level: demo.level, label: demo.label, waveT: m.waveT, bubbleT: m.bubbleT, wake: m.hover, tilt: m.tiltScaled, ripple: m.ripple, tint: TINT[id], style: "split", scale: 1.55, working: demo.working, phase: (id.length * 0.37) % 6 });
    d.ctx.clearRect(0, 0, 256, 256);
    d.ctx.drawImage(dockRenderer.canvas, 0, 0, 256, 256);
  }
  function drawLab() {
    const m = lab.motion;
    const label = lab.id === "workbuddy" ? `${Math.round(6068 * lab.level / 100 / 100) / 10}k` : undefined;
    labRenderer.render({ id: lab.id, level: lab.level, label, waveT: m.waveT, bubbleT: m.bubbleT, wake: m.hover, tilt: m.tiltScaled, ripple: m.ripple, tint: TINT[lab.id], style: lab.style, scale: 1.55, working: DEMO[lab.id].working, phase: 0.7 });
  }
  function drawDodge() {
    const m = dodge.motion;
    const level = dodge.manualLevel !== null ? dodge.manualLevel : (reduceMotion ? 22 : 52 + 34 * Math.sin(dodge.t * 0.85));
    dockRenderer.render({ id: "antigravity", level, waveT: m.waveT, bubbleT: m.bubbleT, wake: m.hover, tilt: m.tiltScaled, ripple: m.ripple, tint: TINT.antigravity, style: "pill", scale: 1.5 });
    dodgeCtx.clearRect(0, 0, 512, 512);
    dodgeCtx.drawImage(dockRenderer.canvas, 0, 0, 512, 512);
    $("#dodgeVal").textContent = `${Math.round(level)}%`;
    $("#dodgeBar").style.width = `${level}%`;
  }

  // Interactive scrubbing on Card 3 (Low-water auto dodge)
  let dodgeTouchReset = 0;
  function scrubDodge(e) {
    clearTimeout(dodgeTouchReset);
    const r = dodge.art.getBoundingClientRect();
    const pct = clamp(Math.round(((e.clientX - r.left) / Math.max(1, r.width)) * 96 + 4), 4, 100);
    if (dodge.manualLevel !== null && Math.abs(pct - dodge.manualLevel) > 1 && dodge.motion) {
      dodge.motion.kick(clamp((pct - dodge.manualLevel) * 0.04, -0.5, 0.5));
    } else if (dodge.manualLevel === null && dodge.motion) {
      dodge.motion.kick(0.35);
    }
    dodge.manualLevel = pct;
    if (reduceMotion && dockRenderer) drawDodge();
    ensureLoop();
  }
  dodge.art.addEventListener("pointerdown", (e) => { if (e.pointerType === "touch") scrubDodge(e); });
  dodge.art.addEventListener("pointermove", scrubDodge);
  dodge.art.addEventListener("pointerleave", (e) => {
    if (e.pointerType === "touch") {
      clearTimeout(dodgeTouchReset);
      dodgeTouchReset = setTimeout(() => { dodge.manualLevel = null; ensureLoop(); }, 2600);
    } else {
      dodge.manualLevel = null;
    }
  });

  let rafId = 0, lastT = 0;
  function ensureLoop() {
    if (reduceMotion || rafId || !dockRenderer) return;
    lastT = performance.now();
    rafId = requestAnimationFrame(frame);
  }
  function frame(now) {
    rafId = 0;
    const dt = Math.min(0.05, (now - lastT) / 1000);
    lastT = now;
    let busy = false;

    if (stageVisible) {
      for (const [id, d] of Object.entries(dockTiles)) {
        const m = d.motion;
        if (!m) continue;
        if (m.target === 0 && m.hover === 0) { d.item.classList.remove("awake"); continue; }
        m.step(dt);
        d.item.classList.add("awake");
        drawDockTile(id, d);
        busy = true;
      }
    }

    if (lab.visible && lab.motion) {
      if (lab.tween) {
        const p = clamp((now - lab.tween.t0) / lab.tween.dur, 0, 1);
        const e = p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2;
        lab.target = lab.tween.from + (lab.tween.to - lab.tween.from) * e;
        lab.level = lab.target;
        syncLevelUI();
        if (p >= 1) { lab.tween = null; syncDrainBtn(); }
        lab.motion.ripple = Math.max(lab.motion.ripple, 0.1);
      } else {
        lab.level += (lab.target - lab.level) * Math.min(1, dt * 7);
      }
      if (lab.pdx) { lab.motion.kick(clamp(lab.pdx * 7, -1.1, 1.1)); lab.pdx = 0; }
      if (now - lab.lastAuto > 3600 && now - lastTouch > 2500) { lab.lastAuto = now; lab.motion.kick((Math.random() > 0.5 ? 1 : -1) * 0.45); }
      lab.motion.step(dt);
      drawLab();
      busy = true;
    }

    if (dodge.visible && dodge.motion) {
      if (dodge.manualLevel === null) dodge.t += dt;
      dodge.motion.step(dt);
      drawDodge();
      busy = true;
    }

    if (busy) rafId = requestAnimationFrame(frame);
  }

  /* ---------------- Lab controls */
  const labApps = $("#labApps");
  labApps.innerHTML = LAB_APPS.map((id) => `<button type="button" class="chip${id === lab.id ? " on" : ""}" data-app="${id}" role="radio" aria-checked="${id === lab.id}"><img src="${ICON(id)}" alt="" />${DEMO[id].name}</button>`).join("");
  const levelInput = $("#labLevel");
  const levelOut = $("#labLevelOut");

  function syncLabTint() {
    const c = TINT[lab.id];
    levelInput.style.setProperty("--tint", c);
    document.getElementById("lab").style.setProperty("--tint", c);
  }
  labApps.addEventListener("click", (e) => {
    const b = e.target.closest("[data-app]");
    if (!b) return;
    lab.id = b.dataset.app;
    $$(".chip", labApps).forEach((c) => { c.classList.toggle("on", c === b); c.setAttribute("aria-checked", String(c === b)); });
    lab.target = DEMO[lab.id].level; lab.tween = null;
    if (lab.motion) { lab.motion.hover = 0.35; lab.motion.kick(0.9); }
    syncLevelUI(true); syncLabTint(); syncDrainBtn();
    if (reduceMotion && labRenderer) { lab.level = lab.target; drawLab(); }
    const fb = $("#labFallback"); if (!fb.hidden) fb.src = ICON(lab.id);
    ensureLoop();
  });

  function syncLevelUI(fromTarget) {
    const v = Math.round(fromTarget ? lab.target : lab.level);
    levelInput.value = v;
    levelInput.style.setProperty("--p", `${((v - 4) / 96) * 100}%`);
    levelOut.textContent = `${v}%`;
  }
  levelInput.addEventListener("input", () => {
    userTouched();
    lab.tween = null;
    lab.target = Number(levelInput.value);
    if (lab.motion) lab.motion.ripple = Math.max(lab.motion.ripple, 0.18);
    syncLevelUI(true); syncDrainBtn();
    if (reduceMotion && labRenderer) { lab.level = lab.target; drawLab(); }
    ensureLoop();
  });

  const drainBtn = $("#labDrain");
  function syncDrainBtn() { $("span", drainBtn).textContent = t(lab.target > 40 ? "lab.drain" : "lab.refill"); }
  drainBtn.addEventListener("click", () => {
    userTouched();
    const to = lab.level > 40 ? 12 : 100;
    lab.tween = { from: lab.level, to, t0: performance.now(), dur: 3600 * Math.abs(to - lab.level) / 88 + 400 };
    lab.target = to;
    syncDrainBtn();
    if (lab.motion) lab.motion.kick(0.6);
    ensureLoop();
  });
  langListeners.push(syncDrainBtn);

  const seg = $("#labStyle");
  seg.addEventListener("click", (e) => {
    const b = e.target.closest("[data-style]");
    if (!b) return;
    lab.style = b.dataset.style;
    $$("[data-style]", seg).forEach((x, i) => { x.classList.toggle("on", x === b); if (x === b) seg.dataset.active = String(i); });
    if (lab.motion) lab.motion.kick(0.5);
    if (reduceMotion && labRenderer) drawLab();
    ensureLoop();
  });

  const labTile = $("#labTile");
  labTile.addEventListener("pointermove", (e) => {
    userTouched();
    const w = labTile.clientWidth || 1;
    if (lab.px !== null) lab.pdx += (e.clientX - lab.px) / w;
    lab.px = e.clientX;
  });
  labTile.addEventListener("pointerleave", () => { lab.px = null; });
  watchVisible(labTile, (v) => { lab.visible = v; if (v) ensureLoop(); });
  watchVisible(dodge.canvas, (v) => { dodge.visible = v; if (v) ensureLoop(); });

  /* ================================================================== MARQUEE (deferred after hero icons) */
  const mq = $("#marquee");
  setTimeout(() => {
    const mqHtml = APPS.map((a) => `<img src="${ICON(a[0])}" alt="${appName(a[1])}" title="${appName(a[1])}" loading="lazy" decoding="async" width="52" height="52" />`).join("");
    mq.innerHTML = mqHtml + mqHtml;
  }, 120);

  /* ================================================================== IDLE VIZ */
  (function idlePath() {
    let d = "M0 70";
    for (let x = 0; x <= 300; x += 3) {
      const burst = (c, w, a) => Math.exp(-Math.pow((x - c) / w, 2)) * a * Math.abs(Math.sin(x * 0.9));
      const y = 70 - burst(120, 14, 46) - burst(210, 10, 30) - burst(268, 8, 22);
      d += ` L${x} ${y.toFixed(1)}`;
    }
    $("#idlePath").setAttribute("d", d);
  })();

  /* ================================================================== STYLES GRID */
  function renderStyles() {
    const labels = t("styles.labels");
    const grid = $("#styleGrid");
    if (!grid.children.length) {
      grid.innerHTML = labels.map((_, i) => {
        const n = String(i).padStart(2, "0");
        return `<figure class="style-cell reveal"><video src="assets/styles/style_${n}.mp4?v=${ASSET_V}" muted loop playsinline webkit-playsinline preload="metadata" aria-hidden="true"></video><span class="n">${n}</span><span data-style-label="${i}"></span></figure>`;
      }).join("");
      $$("video", grid).forEach((v) => {
        v.defaultMuted = true;
        v.muted = true;
        v.playsInline = true;
        v.addEventListener("loadedmetadata", () => {
          if (v.paused && v.currentTime === 0) {
            try { v.currentTime = 0.01; } catch (_) {}
          }
        }, { once: true });
        watchVisible(v, (vis) => {
          if (vis && !reduceMotion) {
            v.muted = true;
            v.play().catch(() => {});
          } else {
            v.pause();
          }
        });
      });
      observeReveals(grid);
    }
    $$("[data-style-label]", grid).forEach((s) => (s.textContent = labels[Number(s.dataset.styleLabel)]));
  }
  langListeners.push(renderStyles);

  /* ================================================================== APPS GRID */
  let appFilter = "all";
  function renderApps() {
    const grid = $("#appGrid");
    if (!grid.children.length) {
      grid.innerHTML = APPS.map((a) => `<li data-cat="${a[2]}"><img src="${ICON(a[0])}" alt="" loading="lazy" width="58" height="58" /><span data-app-name="${a[0]}"></span><i style="background:${a[3]}"></i></li>`).join("") +
        `<li class="app-more" data-cat="more"><span class="more-badge">30+</span><span data-more-label></span><i style="background:#587BA3"></i></li>`;
    }
    $$("[data-app-name]", grid).forEach((s) => { const a = APPS.find((x) => x[0] === s.dataset.appName); s.textContent = appName(a[1]); });
    const moreLbl = $("[data-more-label]", grid);
    if (moreLbl) moreLbl.textContent = t("apps.more");
    const counts = { all: "30+", c: 0, a: 0 };
    APPS.forEach((a) => counts[a[2]]++);
    const fs = [["all", "apps.all"], ["c", "apps.coding"], ["a", "apps.ai"]];
    $("#appFilters").innerHTML = fs.map(([k, key]) => `<button type="button" class="filter${k === appFilter ? " on" : ""}" data-f="${k}">${t(key)}<sup>${counts[k]}</sup></button>`).join("");
    $$("li", grid).forEach((li) => li.classList.toggle("dim", appFilter !== "all" && li.dataset.cat !== "more" && li.dataset.cat !== appFilter));
  }
  $("#appFilters").addEventListener("click", (e) => {
    const b = e.target.closest("[data-f]");
    if (!b) return;
    appFilter = b.dataset.f;
    renderApps();
  });
  langListeners.push(renderApps);

  /* ================================================================== CHANGELOG (Keep-a-Changelog + SemVer) */
  const CHANGELOG_ENTRIES = [
    {
      ver: "v1.3.5", id: "v1-3-5", date: "2026-11-25", latest: true,
      title: [
        "Restored full-contrast mineral plan nameplate in Menu Bar popover",
        "修复菜单栏套餐矿石铭牌透明发虚问题（保留完整深底与一键菜单）",
      ],
      summary: [
        "Replaces SwiftUI borderless Menu wrapping on the Menu Bar plan badge with a full-fidelity plain button + native NSMenu popup so plan multiplier nameplates stay crisp on macOS 26 Tahoe.",
        "移除 macOS 26 Tahoe 上会剥离胶囊底色的无边框 Menu 包装，改用原生高对比矿石铭牌按钮配合 NSMenu 弹出菜单，视觉与悬停卡片 100% 统一。",
      ],
      groups: [
        ["fixed", [
          [
            "<b>Crisp Anodized Mineral Plan Nameplate (<code>InteractivePlanBadgeButton</code>)</b>: Fixed <code>Pro Lite · 5x</code> / <code>AI Ultra · 20x</code> badges appearing transparent inside the Menu Bar popover on macOS 26 Tahoe while preserving 1-click multiplier switching.",
            "<b>菜单栏套餐铭牌满血高对比渲染</b>：彻底解决 <code>Pro Lite · 5x</code> / <code>AI Ultra · 20x</code> 徽章背景变透明看不清的问题，同时保持点击原地弹出原生菜单一键切换倍率。",
          ],
        ]],
      ],
    },
    {
      ver: "v1.3.4", id: "v1-3-4", date: "2026-11-25",
      title: [
        "End-to-end Ed25519 OTA & atomic rollback, off-main-thread Mach IPC & strict account isolation",
        "全链路 Ed25519 验签与内核原子回滚、离主线程 Dock IPC 与严格多账号隔离加固",
      ],
      summary: [
        "Fixes all 18 findings from a full cross-model codebase security & reliability audit: enforces Ed25519 verification on every update path, upgrades installs to kernel-atomic renamex_np swap with auto-rollback, fixes WebUsageFetcher concurrency & Mach bootstrap port leaks, and hardens account/pool/product isolation.",
        "针对全仓深度代码审查一次性修复 18 项安全与稳定性隐患：全链路强制 Ed25519 验签与内核级原子替换回滚、修复网页刷新队列竞态与 Mach 端口泄漏、彻底加固多账号/多池/跨产品隔离与发布门禁。",
      ],
      groups: [
        ["fixed", [
          [
            "<b>End-to-End Ed25519 Verification &amp; Kernel-Atomic <code>renamex_np</code> Rollback</b>: GitHub fallback and <code>install.sh</code> now strictly require Ed25519-signed <code>latest.json</code> + SHA-256 + bundle version/signature verification; OTA, terminal, and DMG upgraders perform same-volume atomic swaps and roll back automatically if launch fails.",
            "<b>全链路 Ed25519 强制验签与内核原子回滚</b>：GitHub 回退源与 <code>install.sh</code> 统一执行 Ed25519 + SHA-256 + 解包元数据校验；OTA、终端安装器与 DMG 助手统一采用同卷 <code>renamex_np</code> 原子交换并在启动异常时自动回滚。",
          ],
          [
            "<b>Zero-Stall <code>WebUsageFetcher</code> Queue, Off-Main-Thread Dock IPC &amp; Port Leak Fix</b>: Eliminated FIFO handoff races &amp; stale JS callbacks in <code>WebUsageFetcher</code>, fixed <code>TASK_BOOTSTRAP_PORT</code> send-right leak in <code>NativeDockTile.c</code>, moved Dock Mach IPC to a dedicated serial queue with <code>pendingReleases</code> compensation, and added a <code>2.5s</code> timeout on Claude Keychain probes.",
            "<b>网页队列防卡死、离主线程 Dock IPC 与端口泄漏修复</b>：消除 <code>WebUsageFetcher</code> 续体丢失与旧回调串台；修复 <code>NativeDockTile.c</code> bootstrap 端口泄漏并将 Dock IPC 迁出主线程配合失败补偿释放；为 Claude Keychain 探针增加 <code>2.5s</code> 硬超时。",
          ],
          [
            "<b>Strict Account, Pool &amp; Cross-Product Isolation</b>: Unified <code>Cursor</code> ↔ <code>Grok Bot</code> sharing checks (exact slot/email + both valid reset epochs within <code>&le;300s</code>), identity-keyed caches &amp; transient-error guards, fixed Antigravity single-pool fallback &amp; Gemini CLI cache tagging, unified <code>1970</code> reset-date sanitization, and guarded website <code>localStorage</code> access.",
            "<b>严格多账号、模型池与跨产品隔离</b>：<code>Cursor</code> ↔ <code>Grok Bot</code> 共享强制要求精确槽位/邮箱且双有效重置时间差 <code>&le;300s</code>；缓存与报错保留严格按账号隔离；修复 Antigravity 缺池借用与 Gemini CLI 缓存越界；全量过滤 <code>1970</code> 哨兵时间，并修复官网无痕模式存储异常。",
          ],
        ]],
      ],
    },
    {
      ver: "v1.3.3", id: "v1-3-3", date: "2026-11-25",
      title: [
        "Unified 3x/5x/20x plan multipliers, zero-IPC Dock hover optimization & automated release gates",
        "全平台 3x / 5x / 20x 套餐倍率引擎、零阻塞 Dock 悬停优化与自动化测试门禁",
      ],
      summary: [
        "Unifies 3x/5x/20x plan multipliers and per-account memory across Antigravity, Gemini, ChatGPT/Codex, Claude, Cursor and Grok Bot, eliminates 60Hz/30Hz main-thread Dock IPC stalls, cuts idle CLI spawns by ~65%, and introduces fast offline swift test guardrails.",
        "全面统一 Antigravity / Gemini、ChatGPT / Codex、Claude、Cursor 与 Grok Bot 的 3x / 5x / 20x 倍率识别与按邮箱记忆，消除 60Hz/30Hz Dock 主线程高频 IPC 阻塞并将闲置期 CLI 唤醒降低约 65%，同时沉淀 AGENTS.md 规范与离线单元测试发布门禁。",
      ],
      groups: [
        ["fixed", [
          [
            "<b>Unified Cross-Platform <code>3x / 5x / 20x</code> Multiplier Engine &amp; 1-Click Menu Bar Switcher</b>: Automatically detects and preserves <code>AI Ultra · 5x / 20x</code>, <code>Pro Lite · 5x</code> / <code>Pro · 20x</code>, <code>Max · 5x / 20x</code>, <code>Pro+ · 3x</code> / <code>Ultra · 20x</code>, and <code>Heavy · 20x</code> without truncation; clicking the plan pill in the Menu Bar or Settings switches multipliers in <code>&lt;1ms</code> and remembers each <code>(app, email)</code> independently.",
            "<b>全平台统一 <code>3x / 5x / 20x</code> 倍率引擎与菜单栏一键切换</b>：自动识别并无截断展示 <code>AI Ultra · 5x / 20x</code>、<code>Pro Lite · 5x</code> / <code>Pro · 20x</code>、<code>Max · 5x / 20x</code>、<code>Pro+ · 3x</code> / <code>Ultra · 20x</code>、<code>Heavy · 20x</code>；点击菜单栏套餐徽章即可 <code>&lt;1ms</code> 切换倍率并按「应用 + 邮箱」独立记忆。",
          ],
          [
            "<b><code>agy 1.5.16</code> Delayed <code>plan_tier</code> Sync &amp; <code>tick()</code> Multi-Variant Lock</b>: Continuously reads <code>agy</code> status output until <code>plan_tier</code> populates (~1s after quota), isolates cached tiers by email, and passes <code>preferredBundleID</code> on every 30fps Dock redraw.",
            "<b><code>agy 1.5.16</code> 套餐异步补读与 <code>tick()</code> 多变体锁定</b>：持续等待 <code>plan_tier</code> 字段就绪并将缓存按邮箱严格隔离，同时补齐 30fps 渲染循环中的 <code>preferredBundleID</code> 传递。",
          ],
        ]],
        ["improved", [
          [
            "<b>Zero-IPC 60Hz/30Hz Dock Loop &amp; Activity-Aware CLI Caching</b>: Caches <code>DockLocator.currentOrientation()</code> (<code>3s</code>) and the <code>com.apple.dock.server</code> Mach send right, reuses active tiles via <code>&lt;1µs</code> <code>kill(pid, 0)</code>, lowers <code>mach_msg</code> send timeout from <code>100ms</code> to <code>16ms</code>, and extends idle CLI TTL when local DB/history mtimes are unchanged (<code>~65%</code> fewer idle spawns).",
            "<b>零阻塞 60Hz/30Hz Dock 悬停渲染与活动感知 CLI 缓存</b>：缓存 Dock 方位与 <code>com.apple.dock.server</code> Mach 端口、通过 <code>kill(pid, 0)</code> 零开销复用活跃图块、将 <code>mach_msg</code> 超时压降至 <code>16ms</code>，并在本地会话无更新时拉长后台 CLI 缓存（闲置期唤醒降低约 <code>65%</code>）。",
          ],
          [
            "<b><code>AGENTS.md</code> Invariants, Single <code>VERSION</code> Source &amp; <code>swift test</code> Release Gate</b>: Adds a 12-case offline <code>AgentGaugeCoreTests</code> suite, <code>Scripts/sync_version.sh</code>, and <code>Scripts/verify_release.sh</code> guarding every future release.",
            "<b><code>AGENTS.md</code> 工程红线、单一 <code>VERSION</code> 源与 <code>swift test</code> 发布门禁</b>：沉淀 12 项核心回归离线单元测试、一键版本同步脚本与全自动发布前校验门禁。",
          ],
        ]],
      ],
    },
    {
      ver: "v1.3.2", id: "v1-3-2", date: "2026-11-24",
      title: [
        "WYSIWYG Dock water color, real Claude / GPT model labels & AI Ultra 5x/20x tiers",
        "Dock 水色所见即所得、Antigravity Claude / GPT 真实模型名与 AI Ultra 5x/20x 档位",
      ],
      summary: [
        "Keeps Dock liquid water 100% faithful to your selected custom or brand color at all quota levels, labels Antigravity's third-party model pool accurately as Claude / GPT, adds Google AI Ultra 5x / 20x badges, and fixes 1970 sentinel reset timestamps.",
        "Dock 图标水波不再因低水位强制变黄/变红，所选颜色 100% 所见即所得；Antigravity 第三方池更正为实际模型名 Claude / GPT，补齐 Google AI Ultra 5x / 20x 档位徽章，并修复未消耗池的 1970 哨兵时间戳误报。",
      ],
      groups: [
        ["fixed", [
          [
            "<b>100% WYSIWYG Dock Water Color</b>: Removed hardcoded <code>&le;30%</code> amber and <code>&le;15%</code> red tint overrides inside <code>NativeIconRenderer</code> so Dock water and badges always preserve your chosen color, while keeping low-quota amber/red bars cleanly inside hover cards, menu bar rows, and Settings cards.",
            "<b>Dock 水色 100% 所见即所得</b>：移除 <code>NativeIconRenderer</code> 在 <code>&le;30%</code> / <code>&le;15%</code> 下强制覆盖水体和徽标颜色的逻辑，无论余量多少均忠实呈现所选颜色/主题色，低额度变橙/红提醒统一保留在悬停与面板进度条上。",
          ],
          [
            "<b><code>Claude / GPT</code> Model Pool Naming, <code>AI Ultra · 5x / 20x</code> Badges &amp; Epoch Sentinel Fix</b>: Replaced vendor label <code>Anthropic</code> with actual model family <code>Claude / GPT</code> across Antigravity windows and switchers, added <code>AI Ultra · 5x</code> / <code>20x</code> pill &amp; subtitle support, and filtered Unix epoch <code>1970-01-01</code> sentinels on untouched <code>100%</code> pools so they honestly show <code>未消耗</code>.",
            "<b>Antigravity <code>Claude / GPT</code> 真实模型命名、<code>AI Ultra · 5x / 20x</code> 档位与哨兵时间修复</b>：将第三方池由厂商名「Anthropic」更正为实际模型名 <code>Claude / GPT</code>，新增 <code>AI Ultra · 5x / 20x</code> 徽章与一键标注，并过滤未消耗池返回的 <code>1970-01-01</code> 哨兵时间。",
          ],
        ]],
      ],
    },
    {
      ver: "v1.3.1", id: "v1-3-1", date: "2026-11-23",
      title: [
        "Cross-product quota boundary isolation (Gemini.app vs Antigravity, Grok.app vs Grok Bot) & anti-noise scraping",
        "全目录跨产品独立额度池硬隔离（Gemini.app / Antigravity、Grok.app / Grok Bot）与防误采校准",
      ],
      summary: [
        "Decouples standalone consumer apps from developer coding-agent quota pools even under the same subscription account, eliminates conversational false positives during web scraping, and locks multi-variant Dock tiles strictly to the hovered bundle ID.",
        "即便登录同一订阅账号，消费级对话客户端与开发者编程智能体亦拥有独立计费桶与重置时间：彻底解耦 Gemini.app 与 Antigravity、Grok.app 与 Grok Bot，剥离聊天文本防误采，并锁定多变体 Dock 图标精准投递。",
      ],
      groups: [
        ["fixed", [
          [
            "<b>Strict Product-Boundary Quota Isolation (<code>Gemini.app</code> vs <code>Antigravity</code>, <code>Grok.app</code> vs <code>Grok Bot</code>)</b>: Standalone <code>Gemini.app</code> (<code>com.google.GeminiMacOS</code>) never borrows <code>Antigravity</code> developer buckets and instead parses <code>gemini.google.com/usage</code> (<code>Current usage</code> + <code>Weekly limit</code>) directly; consumer <code>Grok.app</code> (<code>com.grokapp.desktop</code>) never borrows <code>Grok Bot</code> coding quota; and <code>Cursor</code> ↔ <code>Grok Bot</code> additionally checks <code>&le;300s</code> reset-epoch agreement.",
            "<b>跨产品线独立额度池硬隔离（<code>Gemini.app</code> vs <code>Antigravity</code>、<code>Grok.app</code> vs <code>Grok Bot</code>）</b>：独立版 <code>Gemini.app</code> 不再借用 <code>Antigravity</code> 开发者池，改为专属解析 <code>gemini.google.com/usage</code>「当前用量 + 每周限额」；消费级 <code>Grok.app</code> 不再借用 <code>Grok Bot</code> 编程周额度；<code>Cursor</code> ↔ <code>Grok Bot</code> 额外校验重置时间偏差（<code>&le;5 分钟</code>）防串池。",
          ],
          [
            "<b>Anti-Noise DOM Quota Extraction, Console Billing URLs &amp; Multi-Variant Dock Targeting</b>: <code>GenericWebUsageProvider</code> strips chat messages, <code>&lt;pre&gt;</code>/<code>&lt;code&gt;</code> blocks, and markdown bodies before quota matching, adds trailing currency parsing (<code>CNY</code>/<code>RMB</code>/<code>USD</code>/<code>元</code>) and <code>360s</code> caching, updates <code>Qwen</code> &amp; <code>MiniMax</code> console billing URLs, and locks <code>NativeTileChannel</code> to the exact hovered <code>bundleID</code> when variants (<code>Zed</code> / <code>Zed Preview</code>, <code>WorkBuddy</code> / <code>CodeBuddy</code>) coexist.",
            "<b>网页会话防误采、控制台账单直达与多变体 Dock 精准投递</b>：网页采集自动剥离聊天气泡与代码块，新增后置币种单位（<code>CNY</code>/<code>RMB</code>/<code>USD</code>/<code>元</code>）识别与快照缓存，校准千问百炼与 MiniMax 余额页入口，并确保多变体应用并存时仅点亮鼠标当前悬停的精确图标。",
          ],
        ]],
      ],
    },
    {
      ver: "v1.3.0", id: "v1-3-0", date: "2026-11-22",
      title: [
        "Ed25519 signed remote push auto-updater & Gemini vs Anthropic dual-pool engine",
        "Ed25519 签名远程推送热更新系统与第一性原理双算力池引擎",
      ],
      summary: [
        "Introduces native one-click remote push OTA updates (Ed25519 + SHA-256 verified, atomic overwrite & restart without Gatekeeper prompts), separates Antigravity's Gemini and Anthropic quota pools, and enforces min(5h, 7d weekly) bottleneck dominance.",
        "新增菜单栏与设置页一键远程推送热更新（Ed25519 签名 + SHA-256 校验、原子覆盖并自动重启、自动清理旧版驻留进程），分离 Antigravity 内 Gemini 与 Anthropic 双算力池，并统一执行多窗口木桶串联定律。",
      ],
      groups: [
        ["added", [
          [
            "<b>Cryptographically Signed Remote Push Auto-Updater (<code>UpdateManager</code>)</b>: Menu bar indicator dot, one-click popover banner, and Settings inspector backed by <code>CryptoKit</code> Ed25519 signatures + SHA-256 verification over <code>usage.komorebi.date/updates/latest.json</code> (with GitHub Releases fallback), atomic <code>/Applications/AgentGauge.app</code> replacement, automatic cleanup of older <code>v1.1–v1.2.1</code> memory processes, and <code>curl -fsSL https://usage.komorebi.date/install.sh | bash</code>.",
            "<b>Ed25519 数字签名远程推送热更新系统（<code>UpdateManager</code>）</b>：支持菜单栏角标、弹窗横幅与设置顶部一键静默下载、原子覆盖 <code>/Applications/AgentGauge.app</code> 并自动重启（免重复触发 Gatekeeper 弹窗），自动接管清理旧版后台进程，并提供终端一行覆盖升级脚本。",
          ],
        ]],
        ["fixed", [
          [
            "<b>Antigravity <code>Gemini</code> vs <code>Anthropic</code> Dual-Pool Isolation</b>: <code>AntigravityProvider</code> now separates <code>gemini-5h</code> / <code>gemini-weekly</code> from <code>3p-5h</code> / <code>3p-weekly</code>, detects the active Desktop conversation model in <code>&lt;0.5ms</code> on Dock hover / Menu Bar wake, labels untouched rolling <code>5h</code> windows as unconsumed, and provides a 4-mode pool selector (<code>Auto</code>, <code>Min Bottleneck</code>, <code>Gemini</code>, <code>Anthropic</code>).",
            "<b>Antigravity 内 <code>Gemini</code> 与 <code>Anthropic</code> 双独立算力池隔离</b>：彻底解决依赖 CLI 默认模型而掩盖 Anthropic 池见底的问题；现支持在靠近 Dock 或打开菜单栏时以 <code>&lt;0.5ms</code> 识别桌面端当前模型池，未消耗的 5h 滚动窗如实标为 <code>未消耗</code>，并提供四档主读数池一键切换。",
          ],
          [
            "<b>Anthropic <code>0..100</code> Utilization Scaling &amp; Series-Gate Bottleneck Law</b>: Fixed <code>ClaudeProvider</code> misreading <code>0.5%–1.0%</code> used as <code>50%–100%</code> used, and enforced <code>min(5h, 7d weekly)</code> across <code>Claude</code> and <code>Codex</code> so an exhausted weekly cap is never masked as <code>100%</code> after a 5-hour session reset.",
            "<b>修复 Claude 低消耗比例跳变与多窗口木桶串联定律</b>：修复 <code>ClaudeProvider</code> 在 <code>&le;1.0%</code> 用量区间的 100 倍缩放错误，并在 <code>Claude</code> 与 <code>Codex</code> 中统一取 <code>min(5h 会话窗口, 7d 周总额度)</code> 作为真实瓶颈余量。",
          ],
        ]],
        ["improved", [
          [
            "<b><code>Dual-Track HUD</code> (#09), Account Isolation &amp; True Manual Refresh</b>: Upgraded <code>Dual-Track HUD</code> to render <code>Gemini + Anthropic</code> pools (or <code>5h + Weekly</code>) with low-quota alert colors, added strict account-slot matching &amp; single-flight deduplication between <code>Cursor</code> and <code>Grok Bot</code>, restored the progress bar in <code>.primaryOnly</code> tooltip mode, and made Manual Refresh invalidate all in-memory caches immediately.",
            "<b>升级双轨微仪表、账号槽位隔离与手动刷新穿透</b>：<code>双轨微仪表</code> 现独立渲染双池或 <code>5h + 周限</code> 双轨并支持低水位变红预警；<code>Cursor</code> 与 <code>Grok Bot</code> 增加严格账号槽位校验与并发合并；补齐「仅主额度」悬停进度条，且手动点击刷新立即穿透全部缓存。",
          ],
        ]],
      ],
    },
    {
      ver: "v1.2.1", id: "v1-2-1", date: "2026-11-22",
      title: [
        "Zero-flicker Schmitt-trigger Dock seam handoff & official Changelog",
        "Dock 图标缝隙零闪烁施密特触发器、多样式混搭片头与官方更新日志",
      ],
      summary: [
        "Eliminates hover boundary oscillation between adjacent Dock icons when macOS Dock Magnification is active, upgrades the 62s film opening to showcase 6 liquid styles side-by-side, and introduces the versioned product Changelog.",
        "彻底解决开启 macOS Dock 放大时鼠标停在相邻图标交界或空隙处来回闪烁切换的问题，重制多样式同屏混搭宣传片头，并上线双语版本更新日志。",
      ],
      groups: [
        ["fixed", [
          [
            "<b>No more Dock boundary or inter-icon seam flickering (<code>A ↔ B</code> / <code>On ↔ Off</code>)</b>: <code>OverlayManager</code> previously blended 30Hz live magnified <code>AXFrame</code> coordinates with 60Hz unmagnified baseline <code>cachedDockTiles</code>, letting the two coordinate frames disagree along icon edges. <code>DockLocator</code> now classifies all five <code>AXUIElementCopyElementAtPosition</code> states (<code>.matched</code>, <code>.dockGap</code>, <code>.untrackedItem</code>, <code>.outsideDock</code>, <code>.openMenu</code>) under a single-authority 60Hz state machine with a <code>3.8–5.5pt</code> Schmitt-trigger penetration threshold (<code>~17pt</code> bidirectional deadband) and inter-icon seam hold.",
            "<b>消除 Dock 相邻图标交界与中间缝隙处的来回闪烁跳变</b>：此前 <code>OverlayManager</code> 同时混用了 30Hz 实时放大态 <code>AXFrame</code> 与 60Hz 未放大基线缓存 <code>cachedDockTiles</code>，导致两套坐标系在边缘竞争。现重构 <code>DockLocator</code> 五态分类状态机，由单一 60Hz 权威状态机配合 <code>3.8–5.5pt</code> 施密特触发器（双向约 <code>17pt</code> 迟滞死区）与空隙保持带，在任意停留点实现零闪烁锁定。",
          ],
        ]],
        ["added", [
          [
            "<b>Interactive Website Changelog &amp; Repository <code>CHANGELOG.md</code></b>: Bilingual version timeline following Keep a Changelog &amp; Semantic Versioning with permanent per-release anchors.",
            "<b>上线官网双语更新日志板块与仓库 <code>CHANGELOG.md</code></b>：遵循 Keep a Changelog 与语义化版本规范，支持单版本锚点直链。",
          ],
        ]],
        ["improved", [
          [
            "<b>Multi-Style Film Opening &amp; <code>30+</code> Ecosystem Matrix</b>: Re-rendered the opening close-ups, 6-icon live Dock bar, and 2×2 draining quartet so <code>Top Timer Scrim</code>, <code>Pixel LED Matrix</code>, <code>Braun Arc Needle</code>, <code>Dual-Track HUD</code>, <code>Dynamic Split</code> and <code>Concentric R-Corner</code> appear side-by-side right from the start.",
            "<b>宣传片开场多样式同屏混搭与 <code>30+</code> 持续扩展矩阵</b>：重制开场高清特写、实景 Dock 6 图标混搭与 2×2 四宫格同步放水画面，开篇即呈现 6 款代表性液态样式的自由组合。",
          ],
        ]],
      ],
    },
    {
      ver: "v1.2.0", id: "v1-2-0", date: "2026-11-22",
      title: [
        "11 curated optical-water styles, pure metered providers & API currency balances",
        "11 款纯图标精选光学水波样式、真实计费厂商提纯与 API 余额直连",
      ],
      summary: [
        "Unifies 11 precision-crafted pure-icon indicators onto the signature refracting bubble-water Metal shader, adds first-class API currency balance pools, and hardens sleep/IPC reliability.",
        "将 11 款纯图标精密余量样式统一至招牌微泡折射液态着色器，新增官方 API 货币余额池一等公民展示，并完成系统休眠与底层 IPC 自愈加固。",
      ],
      groups: [
        ["added", [
          [
            "<b>11 Curated Pure-Icon Liquid Styles</b>: Replaced experimental geometric semicircles with <code>Top Timer Scrim</code>, <code>Dynamic Split</code>, <code>Micro-Halo Text</code>, <code>Concentric R-Corner Dodge</code>, <code>Aperture Sweep</code>, <code>Pixel LED Matrix</code>, <code>Dual-Track HUD</code>, <code>Braun Arc Needle</code>, <code>5-Cell Prism Bar</code>, <code>Dynamic Micro-Island</code> and <code>Top Energy Brow</code> — all running over unified 16-bit optical bubble water.",
            "<b>11 款纯图标精选光学水波样式</b>：移除实验性半圆与外白圈边框，定制截图顶栏时间、动态反相字、微晶描边字、同心 R 角避让、光圈扇叶扫描、像素 LED 点阵、双轨微仪表、博朗圆弧指针、底部 5 格晶块、顶部灵动微岛与顶部弧形光眉，全系共享双层折射微泡水体。",
          ],
          [
            "<b>First-Class API Currency Balances &amp; New Native Providers</b>: Added <code>balanceDisplay</code> / <code>dockBalanceShort</code> for <code>DeepSeek</code> and <code>Kimi</code> currency balance pools (e.g. <code>¥28.50</code> in card, <code>¥29</code> on Dock icon), <code>VS Code (Copilot)</code> via <code>gh api</code>, <code>Windsurf</code> local Protobuf state parsing, <code>MiniMax</code> Coding Plan support, and full offline <code>256×256</code> squircle icons.",
            "<b>官方 API 货币余额池与多家原生 Provider</b>：支持 DeepSeek / Kimi 货币余额展示（悬停卡片显示 <code>¥28.50</code>、Dock 图标显示 <code>¥29</code>），新增 VS Code (Copilot) 本地配额、Windsurf 本地状态解析、MiniMax 接入及全量 <code>256×256</code> 离线兜底图标。",
          ],
        ]],
        ["improved", [
          [
            "<b>First-Principles Metering Purification (Zero Fake <code>100%</code>)</b>: Purged non-metered local browsers, orchestrators and BYOK shells; unauthenticated providers strictly return <code>nil</code> rather than fabricating <code>100%</code>.",
            "<b>第一性原理计费目录提纯与「零假 100%」铁律</b>：剔除本地浏览器与无独立计费的空壳客户端；未认证状态严格返回空值，绝不伪造 <code>100%</code>。",
          ],
          [
            "<b>Gravity-Stabilized Wave Physics &amp; Low-Water Contrast</b>: Locked horizontal equilibrium (<code>targetTilt = 0</code>) with near-critical spring damping (<code>20 / 8.4</code>), and boosted scrim contrast on white icons (<code>ChatGPT</code>, <code>Antigravity</code>) at <code>14%–24%</code> low water.",
            "<b>重力稳态液面物理与浅色图标低水位增强</b>：移除异步倾角写冲突，升级近临界阻尼弹簧，并为纯白/浅色图标在 <code>14%–24%</code> 低水位区间自适应加深底衬对比度。",
          ],
          [
            "<b>Zero-Power Sleep &amp; Self-Healing Mach IPC</b>: Added <code>NSWorkspace</code> sleep/wake suspension, a 5s <code>NativeTileChannel</code> circuit breaker, strict DNS-boundary cookie matching, and deterministic subprocess reaping.",
            "<b>合盖休眠零功耗与 Mach 断路自愈</b>：新增睡眠/锁屏自动挂起、Dock 图块 Mach 通道 5 秒熔断自愈、严格域名边界 Cookie 匹配与子进程确定性回收。",
          ],
        ]],
        ["fixed", [
          [
            "<b>Restored Antigravity &amp; Gemini <code>AI Ultra</code> Plan Badge</b>: Replaced raw <code>openpty</code> with unbuffered <code>/usr/bin/script -q -F</code> + <code>/credits</code> redraw, scalar ANSI stripping, <code>AntigravityCLISingleFlight</code> deduplication, and 24h per-account caching.",
            "<b>修复 Antigravity 与 Gemini <code>AI Ultra</code> 套餐等级识别</b>：采用无缓冲伪终端重绘与纯 Swift 标量状态机剥离 ANSI 序列，配合单飞并发合并与 24 小时账号级缓存。",
          ],
          [
            "<b>Eliminated ChatGPT White-Squircle Seam</b>: Fixed a horizontal optical break across bright white app icons in <code>NativeIconRenderer</code>.",
            "<b>修复 ChatGPT 纯白图标断层伪影</b>：消除高亮度白色图标在水线过渡处的光学断层。",
          ],
        ]],
      ],
    },
    {
      ver: "v1.1.2", id: "v1-1-2", date: "2026-11-21", older: true,
      title: [
        "120Hz horizontal hover rail, per-app anchor lock & open-source release",
        "120Hz 悬停卡片水平导轨锁定、单应用放大防抖与开源双语文档",
      ],
      summary: [
        "Locks hover cards to a constant horizontal rail across the Dock while eliminating magnification wobble, and opens the repository under the MIT License.",
        "锁定跨应用左右切换时的卡片水平导轨，消除 Dock 放大微呼吸导致的水平晃动，并以 MIT 协议开放双语源码仓库。",
      ],
      groups: [
        ["improved", [
          [
            "<b>120Hz Horizontal Rail &amp; Per-App Anchor Lock</b>: Decoupled <code>NSHostingView</code> intrinsic sizing from <code>NSPanel</code> origin positioning so cards glide horizontally without vertical jumps between <code>Grok Bot</code> and <code>WorkBuddy</code>, locking <code>centerX</code> per app once AX-confirmed.",
            "<b>120Hz 水平导轨平移与单应用锚点锁定</b>：解耦自适应视图测量与窗口定位，左右切换不同高度卡片时底边严格对齐同一水平线，并在 AX 确认后锁定单图标中心防止放大呼吸抖动。",
          ],
          [
            "<b>Unified Navbar Utility Capsule &amp; Bilingual Docs</b>: Added the unified GitHub + Language capsule, asset cache-busting, showcase gallery and MIT license.",
            "<b>官网顶部胶囊整合与开源双语文档</b>：统一导航栏 GitHub 与中英切换胶囊，发布双语架构文档与 MIT 开源协议。",
          ],
        ]],
      ],
    },
    {
      ver: "v1.1.0", id: "v1-1-0", date: "2026-11-20", older: true,
      title: [
        "Initial macOS 26 Tahoe release, 16-bit Metal shader & interactive WebGL Lab",
        "macOS 26 Tahoe 原生首发：16-bit Metal 液态着色器、顶栏看板与在线实验室",
      ],
      summary: [
        "First public release bringing live 16-bit half-float Metal liquid gauges to the macOS Dock, paired with a unified menu bar dashboard and browser WebGL shader port.",
        "首次公开发布：将 16-bit 半精度 Metal 实时液态水位带入 macOS Dock，配备一体成型菜单栏全局看板与浏览器实时 WebGL 液态实验室。",
      ],
      groups: [
        ["added", [
          [
            "<b>16-Bit Half-Float Metal Dock Renderer &amp; Watchdog</b>: Dual-wave optical water (<code>~1.7 ms</code>/frame), 24 refracting micro-bubbles, low-water auto-dodge, <code>0%</code> cost at rest, and crash-safe <code>AgentGaugeCleanup</code> restoration.",
            "<b>16-bit 半精度 Metal 渲染管线与守护还原</b>：单帧约 <code>1.7 ms</code> 双层波浪与微泡色散折射、低水位自动避让、闲置零占用，以及异常退出自动复原原生图标。",
          ],
          [
            "<b>Unified Menu Bar Popover, Studio &amp; Website</b>: Single-contour Liquid Glass menu bar dashboard, live badge customization studio, and interactive WebGL Liquid Lab on <code>usage.komorebi.date</code>.",
            "<b>菜单栏全局看板、样式工作台与交互官网</b>：无接缝液态玻璃菜单栏面板、实时水位样式工作台与产品官网。",
          ],
        ]],
      ],
    },
  ];

  const clFeed = $("#changelogFeed");
  const clToggleBtn = $("#clToggleOlder");
  let clShowOlder = /^#v1-1-/.test(location.hash);

  function renderChangelog() {
    if (!clFeed) return;
    clFeed.innerHTML = CHANGELOG_ENTRIES.map((e) => `
      <article class="cl-entry reveal in" id="${e.id}"${e.older && !clShowOlder ? " hidden" : ""}>
        <div class="cl-meta">
          <div class="cl-ver-row">
            <span class="cl-ver">${e.ver}</span>
            ${e.latest ? `<span class="cl-latest">${t("cl.latest")}</span>` : ""}
          </div>
          <time class="cl-date" datetime="${e.date}">${e.date}</time>
          <a class="cl-anchor" href="#${e.id}">#${e.ver}</a>
        </div>
        <div class="cl-body">
          <h3>${bi(e.title)}</h3>
          <p class="cl-summary">${bi(e.summary)}</p>
          <div class="cl-groups">
            ${e.groups.map(([kind, items]) => `
              <div class="cl-group">
                <span class="cl-tag ${kind}">${t(`cl.${kind}`)}</span>
                <ul class="cl-list">${items.map((it) => `<li>${bi(it)}</li>`).join("")}</ul>
              </div>`).join("")}
          </div>
        </div>
      </article>`).join("");
    if (clToggleBtn) {
      $("[data-cl-toggle-lbl]", clToggleBtn).textContent = t(clShowOlder ? "cl.less" : "cl.more");
    }
  }
  if (clToggleBtn) {
    clToggleBtn.addEventListener("click", () => {
      clShowOlder = !clShowOlder;
      renderChangelog();
    });
  }
  window.addEventListener("hashchange", () => {
    if (/^#v1-1-/.test(location.hash) && !clShowOlder) {
      clShowOlder = true;
      renderChangelog();
      const target = document.getElementById(location.hash.slice(1));
      if (target) target.scrollIntoView({ behavior: "smooth" });
    }
  });
  langListeners.push(renderChangelog);

  /* ================================================================== FILM */
  const filmFrame = $(".film-frame");
  const filmVideo = $("#filmVideo");
  filmVideo.removeAttribute("controls");
  $("#filmPlay").addEventListener("click", () => {
    filmFrame.classList.add("playing");
    filmVideo.setAttribute("controls", "");
    filmVideo.play().catch(() => {});
  });
  filmVideo.addEventListener("play", () => { filmVideo.setAttribute("controls", ""); filmFrame.classList.add("playing"); });
  filmVideo.addEventListener("ended", () => filmFrame.classList.remove("playing"));
  const modal = $("#filmModal"), modalVideo = $("#modalVideo");
  $$("[data-film-open]").forEach((b) => b.addEventListener("click", () => { modal.hidden = false; modalVideo.currentTime = 0; modalVideo.play().catch(() => {}); }));
  function closeModal() { modalVideo.pause(); modal.hidden = true; }
  $$("[data-film-close]").forEach((b) => b.addEventListener("click", closeModal));
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      if (!modal.hidden) closeModal();
      else if (pop.classList.contains("open")) setPop(false);
    }
  });

  /* ================================================================== BOOT */
  const qa = new URLSearchParams(location.search).get("qa");
  if (new URLSearchParams(location.search).has("qa")) document.documentElement.classList.add("qa");
  if (qa && document.getElementById(qa)) {
    for (const s of $$("main > section")) { if (s.id === qa) break; s.style.display = "none"; }
  }
  applyLang(pickLang(), false);
  syncLabTint();
  syncLevelUI(true);
  observeReveals();
  onScroll();
  fitStage();
  fitBentoPop();
  initLiquid();
  window.addEventListener("resize", () => { if (pop.classList.contains("open")) placePop(); });
})();
