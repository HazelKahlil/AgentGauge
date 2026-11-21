/* AgentGauge website · native macOS 26 Tahoe interactive experience */
(function () {
  "use strict";

  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const I18N = window.AG_I18N;
  const ICON = (id) => `assets/icons/${id}.png`;

  /* ------------------------------------------------------------------ 50 supported apps */
  const APPS = [
    ["codex", "ChatGPT / Codex", "c", "#3E8C79"], ["antigravity", "Antigravity", "c", "#5479B2"], ["cursor", "Cursor", "c", "#7165AD"],
    ["grokbot", "Grok Bot", "c", "#B37452"], ["muse", "Muse", "c", "#4E7CA8"], ["claude", "Claude", "c", "#AD6E54"],
    ["workbuddy", "WorkBuddy", "c", "#498596"], ["multica", "Multica", "c", "#7A67A6"], ["hermes", "Hermes", "c", "#A3687E"],
    ["windsurf", "Windsurf", "c", "#428E85"], ["trae", "Trae", "c", "#4C9468"], ["kiro", "Kiro", "c", "#7C62AD"],
    ["zed", "Zed", "c", "#4A6FA5"], ["vscode", "VS Code", "c", "#4878A8"], ["warp", "Warp", "c", "#4A86A8"],
    ["qoder", "Qoder", "c", "#6368A8"], ["devin", "Devin", "c", "#458C86"], ["xcode", "Xcode", "c", "#4F7BB0"],
    ["intellij", "IntelliJ IDEA", "d", "#AD5F6E"], ["pycharm", "PyCharm", "d", "#4A9476"], ["webstorm", "WebStorm", "d", "#468996"],
    ["androidstudio", "Android Studio", "d", "#529672"], ["opencode", "OpenCode", "d", "#AD824C"],
    ["gemini", "Gemini", "a", "#597AB2"], ["grok", "Grok", "a", "#788494"], ["deepseek", "DeepSeek", "a", "#536DA8"],
    ["perplexity", "Perplexity", "a", "#3E7C87"], ["doubao", ["Doubao", "豆包"], "a", "#547EB0"], ["kimi", "Kimi", "a", "#6B7685"],
    ["qwen", ["Qwen", "通义千问"], "a", "#6A64A8"], ["cherrystudio", "Cherry Studio", "a", "#AD5E5E"], ["lmstudio", "LM Studio", "a", "#755FA6"],
    ["chatcut", "ChatCut", "a", "#7A6BA8"], ["manus", "Manus", "a", "#6B7685"], ["kaze", "Kaze", "a", "#4E7FA6"],
    ["tabbit", "Tabbit", "a", "#5C7FAE"], ["quark", ["Quark", "夸克"], "a", "#5470B0"], ["chatglm", ["ChatGLM", "智谱清言"], "a", "#4F6FB0"],
    ["ollama", "Ollama", "a", "#6E7480"], ["raycast", "Raycast AI", "a", "#B0605E"], ["jan", "Jan", "a", "#B08A4C"],
    ["lechat", "Le Chat", "a", "#B57A4E"], ["poe", "Poe", "a", "#7B66AD"], ["chatbox", "Chatbox", "a", "#B0905C"],
    ["lobechat", "LobeChat", "a", "#B07A5A"], ["anythingllm", "AnythingLLM", "a", "#727985"], ["nextchat", "NextChat", "a", "#5272B0"],
    ["openwebui", "Open WebUI", "a", "#6A6F78"], ["gpt4all", "GPT4All", "a", "#8E9A52"], ["comfyui", "ComfyUI", "a", "#9EA24E"],
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
  const POPOVER_ORDER = ["antigravity", "cursor", "workbuddy", "multica", "grokbot", "gemini", "muse", "codex"];

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
    multica: {
      short: "Multica", title: "Multica", level: 100, reset: ["Online", "运行中"], working: true,
      badge: ["Local", "本地应用"],
      sub: ["Multica Local Runtime", "Multica 本地状态"],
      windows: [
        [["Local Runtime (Uncapped)", "本地运行状态（无独立配额）"], 100, ["Online", "在线"], true],
      ],
      note: ["Local orchestrator — no percentage cap", "本地编排客户端（不设百分比限额）"],
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
    muse: {
      short: "Muse", title: "Muse", level: 91, reset: "9h 00m", defaultPaused: true,
      badge: ["Free", "Free"],
      sub: ["Meta AI · Local Session", "Meta AI · 本地会话"],
      windows: [
        [["Muse Session Quota", "Muse 会话额度"], 91, "9h 00m", true],
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
  const pickLang = () => {
    const q = new URLSearchParams(location.search).get("lang");
    if (q === "zh" || q === "en") return q;
    const s = localStorage.getItem("ag-lang-v2");
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
    if (persist) localStorage.setItem("ag-lang-v2", lang);
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
    const cdText = s.working
      ? (lang === "zh" ? "正在工作中" : "Working")
      : (typeof s.reset === "string" ? (lang === "zh" ? `${s.reset} 重置` : `resets in ${s.reset}`) : bi(s.reset));
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
  let stageScale = 1;
  function fitStage() { stageScale = (stage.clientWidth || 1240) / 1240; inner.style.transform = `scale(${stageScale})`; }
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

  let activeDock = null, hideTipTimer = 0;
  function setDockActive(id) {
    clearTimeout(hideTipTimer);
    if (activeDock === id) return;
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
    const item = dockEl.querySelector(`[data-id="${id}"]`);
    const b = toStage(item);
    const cx = b.x + b.w / 2;
    const name = DEMO[id] ? DEMO[id].name : appName(SYS_LABEL[id] || id);
    labelEl.textContent = name;
    labelEl.style.setProperty("--lx", `${cx}px`);
    labelEl.classList.add("on");

    if (SNAPSHOTS[id]) {
      liveTip.innerHTML = renderHoverCardHTML(id);
      const w = liveTip.offsetWidth || 336;
      const tx = Math.round(clamp(cx - w / 2, 12, 1240 - w - 12));
      liveTip.style.setProperty("--tx", `${tx}px`);
      liveTip.classList.add("on");
      liveTip.setAttribute("aria-hidden", "false");
      const d = dockTiles[id];
      if (d && d.motion) d.motion.kick((Math.random() > 0.5 ? 1 : -1) * 0.65);
    } else {
      liveTip.classList.remove("on");
      liveTip.setAttribute("aria-hidden", "true");
    }
    ensureLoop();
  }
  langListeners.push(() => { if (activeDock && SNAPSHOTS[activeDock]) liveTip.innerHTML = renderHoverCardHTML(activeDock); });

  function updateDockMagnification(stageX) {
    dockItemEls.forEach((item) => {
      if (stageX === null) {
        item.style.setProperty("--ms", "1");
        item.style.setProperty("--dy", "0px");
        return;
      }
      const b = toStage(item);
      const dist = Math.abs(stageX - (b.x + b.w / 2));
      const g = Math.exp(-(dist * dist) / (2 * 50 * 50));
      const scale = 1 + 0.2 * g;
      const dy = -13 * g;
      item.style.setProperty("--ms", scale.toFixed(3));
      item.style.setProperty("--dy", `${dy.toFixed(1)}px`);
    });
  }

  // Hero Stage Menu Bar Popover (seamless single-contour macOS NSPopover geometry)
  const pop = $("#pop");
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
    const left = clamp(g.x + g.w / 2 - 224, 8, 1240 - 448 - 8);
    const cx = g.x + g.w / 2 - left;
    pop.style.left = `${left}px`;
    pop.style.setProperty("--pop-ox", `${((cx / 448) * 100).toFixed(1)}%`);
    const d = popoverContourPath(cx);
    popGlass.style.clipPath = `path("${d}")`;
    popGlass.style.webkitClipPath = `path("${d}")`;
    popRimPath.setAttribute("d", d);
  }
  function setPop(open) {
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
  gauge.addEventListener("pointerenter", () => {
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

  // Clicking desktop wallpaper dismisses popover just like macOS NSPopover (.transient)
  inner.addEventListener("click", (e) => {
    if (!pop.classList.contains("open")) return;
    if (e.target.closest("#pop, #mbGauge, #dock, #wallPlaque")) return;
    userTouched();
    setPop(false);
  });

  // Pointer → Dock
  let lastPX = null;
  dockEl.addEventListener("pointermove", (e) => {
    userTouched();
    const sRect = inner.getBoundingClientRect();
    const stageX = (e.clientX - sRect.left) / stageScale;
    updateDockMagnification(stageX);

    let closestId = null, bestDist = 46;
    dockItemEls.forEach((it) => {
      const b = toStage(it);
      const d = Math.abs(stageX - (b.x + b.w / 2));
      if (d < bestDist) { bestDist = d; closestId = it.dataset.id; }
    });
    setDockActive(closestId);

    if (lastPX !== null && activeDock && dockTiles[activeDock] && dockTiles[activeDock].motion) {
      dockTiles[activeDock].motion.kick(clamp((e.clientX - lastPX) * 0.014, -0.55, 0.55));
    }
    lastPX = e.clientX;
  });
  dockEl.addEventListener("pointerleave", () => {
    lastPX = null;
    updateDockMagnification(null);
    setDockActive(null);
  });
  dockEl.addEventListener("click", (e) => {
    const item = e.target.closest(".dock-item");
    if (!item) return;
    userTouched();
    const id = item.dataset.id;
    if (dockTiles[id] && dockTiles[id].motion) dockTiles[id].motion.kick(0.95);
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
  let popI = 0, stageVisible = false;
  setTimeout(() => setPop(true), reduceMotion ? 0 : 750);
  setInterval(() => {
    if (!stageVisible || reduceMotion || performance.now() - lastTouch < 8000 || !pop.classList.contains("open")) return;
    stagePopover.select(POP_TOUR[++popI % POP_TOUR.length], false);
  }, 3200);
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

  function setBentoHover(id, anim = false) {
    if (!SNAPSHOTS[id]) return;
    const changed = bentoHoverId !== id;
    bentoHoverId = id;
    const idx = Math.max(0, BENTO_HOVER_APPS.indexOf(id));
    bentoMiniSel.style.transform = `translate3d(${idx * 50}px, 0, 0)`;
    bentoTip.innerHTML = renderHoverCardHTML(id);
    if (anim && changed && !reduceMotion) {
      bentoTip.classList.remove("swap");
      void bentoTip.offsetWidth;
      bentoTip.classList.add("swap");
    }
  }
  $$("[data-bento-app]", bentoMiniDock).forEach((btn) => {
    btn.addEventListener("pointerenter", () => setBentoHover(btn.dataset.bentoApp, true));
    btn.addEventListener("click", () => setBentoHover(btn.dataset.bentoApp, true));
  });
  langListeners.push(() => setBentoHover(bentoHoverId));
  setBentoHover("antigravity");

  // Card 2: Full interactive MenuBarPopoverView inside Bento
  mountPopover($("#bentoPopMount"), { staticSurface: true, initial: "cursor" });
  const bentoPopArt = $("#bentoPopArt");
  const bentoPopScale = $("#bentoPopScale");
  function fitBentoPop() {
    const availW = (bentoPopArt.clientWidth || 520) - 24;
    const availH = (bentoPopArt.clientHeight || 400) - 24;
    const sc = Math.min(1, availW / 448, availH / 344);
    bentoPopScale.style.transform = `scale(${sc.toFixed(3)})`;
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
      labRenderer = new AGLiquid.LiquidRenderer(lab.canvas, 1024);

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
  dodge.art.addEventListener("pointermove", (e) => {
    const r = dodge.art.getBoundingClientRect();
    const pct = clamp(Math.round(((e.clientX - r.left) / Math.max(1, r.width)) * 96 + 4), 4, 100);
    if (dodge.manualLevel !== null && Math.abs(pct - dodge.manualLevel) > 1 && dodge.motion) {
      dodge.motion.kick(clamp((pct - dodge.manualLevel) * 0.04, -0.5, 0.5));
    }
    dodge.manualLevel = pct;
    if (reduceMotion && dockRenderer) drawDodge();
    ensureLoop();
  });
  dodge.art.addEventListener("pointerleave", () => { dodge.manualLevel = null; });

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
        return `<figure class="style-cell reveal"><video src="assets/styles/style_${n}.mp4" muted loop playsinline preload="none" aria-hidden="true"></video><span class="n">${n}</span><span data-style-label="${i}"></span></figure>`;
      }).join("");
      $$("video", grid).forEach((v) => watchVisible(v, (vis) => { if (vis && !reduceMotion) { v.play().catch(() => {}); } else { v.pause(); } }));
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
      grid.innerHTML = APPS.map((a) => `<li data-cat="${a[2]}"><img src="${ICON(a[0])}" alt="" loading="lazy" width="58" height="58" /><span data-app-name="${a[0]}"></span><i style="background:${a[3]}"></i></li>`).join("");
    }
    $$("[data-app-name]", grid).forEach((s) => { const a = APPS.find((x) => x[0] === s.dataset.appName); s.textContent = appName(a[1]); });
    const counts = { all: APPS.length, c: 0, d: 0, a: 0 };
    APPS.forEach((a) => counts[a[2]]++);
    const fs = [["all", "apps.all"], ["c", "apps.coding"], ["d", "apps.dev"], ["a", "apps.ai"]];
    $("#appFilters").innerHTML = fs.map(([k, key]) => `<button type="button" class="filter${k === appFilter ? " on" : ""}" data-f="${k}">${t(key)}<sup>${counts[k]}</sup></button>`).join("");
    $$("li", grid).forEach((li) => li.classList.toggle("dim", appFilter !== "all" && li.dataset.cat !== appFilter));
  }
  $("#appFilters").addEventListener("click", (e) => {
    const b = e.target.closest("[data-f]");
    if (!b) return;
    appFilter = b.dataset.f;
    renderApps();
  });
  langListeners.push(renderApps);

  /* ================================================================== FILM */
  const filmFrame = $(".film-frame");
  const filmVideo = $("#filmVideo");
  filmVideo.removeAttribute("controls");
  $("#filmPlay").addEventListener("click", () => { filmVideo.setAttribute("controls", ""); filmVideo.play(); });
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
