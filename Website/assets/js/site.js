// Room, the website. No dependencies, no tracking.
(() => {
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => [...el.querySelectorAll(s)];
  const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
  const ease = (t) => 1 - Math.pow(1 - t, 3);
  const easeInOut = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)');
  const darkScheme = matchMedia('(prefers-color-scheme: dark)');
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch {} },
  };

  // ---------- Hero: the hole in the paper ----------
  //
  // p runs 0 → 1 over the hero's scroll. The hole starts where the mark sits above the
  // title and grows (in log space, so it feels like a camera move) until the print fills
  // the screen; then the window rises onto the print.

  const hero = $('[data-hero]');
  if (hero) {
    const stage = $('.hero-stage', hero);
    const paper = $('[data-hero-paper]', hero);
    const copy = $('[data-hero-copy]', hero);
    const markSpace = $('.hero-mark-space', hero);
    // The glyph point that stays put while the hole grows, and the part of the glyph
    // that is solid enough to cover the viewport at the end (in glyph units, 0…1).
    const anchor = { x: 0.33, y: 0.5 };
    const solid = { w: 0.54, h: 0.88 };
    let geo = null;
    let ticking = false;

    const measure = () => {
      const vw = stage.clientWidth;
      const vh = stage.clientHeight;
      const size = Math.round(clamp(Math.min(vw, vh) * 0.2, 112, 208));
      copy.style.setProperty('--mark-size', `${size}px`);
      const start = { x: markSpace.offsetLeft, y: markSpace.offsetTop, s: size };
      const endS = Math.max(vw / solid.w, vh / solid.h) * 1.04;
      geo = {
        vw, vh,
        s0: start.s, s1: endS,
        a0: { x: start.x + anchor.x * start.s, y: start.y + anchor.y * start.s },
        a1: { x: vw / 2, y: vh / 2 },
        range: hero.offsetHeight - vh,
      };
    };

    const render = () => {
      ticking = false;
      if (!geo) measure();
      const top = hero.getBoundingClientRect().top;
      const p = clamp(-top / geo.range);

      const t = easeInOut(clamp((p - 0.04) / 0.56));
      const s = geo.s0 * Math.pow(geo.s1 / geo.s0, t);
      const ax = geo.a0.x + (geo.a1.x - geo.a0.x) * t;
      const ay = geo.a0.y + (geo.a1.y - geo.a0.y) * t;
      const st = paper.style;
      st.setProperty('--hs', `${s.toFixed(2)}px`);
      st.setProperty('--hx', `${(ax - anchor.x * s).toFixed(2)}px`);
      st.setProperty('--hy', `${(ay - anchor.y * s).toFixed(2)}px`);
      const shadow = 0.28 * (1 - clamp(t * 3));
      st.setProperty('--hole-shadow', shadow.toFixed(3));
      paper.style.filter = shadow < 0.005 ? 'none' : '';
      paper.style.visibility = t > 0.995 ? 'hidden' : '';

      stage.style.setProperty('--print-scale', (1.08 - 0.08 * ease(t)).toFixed(4));

      const c = clamp(p / 0.22);
      copy.style.setProperty('--copy-o', (1 - c).toFixed(3));
      copy.style.setProperty('--copy-y', `${(-c * 70).toFixed(1)}px`);
      copy.style.visibility = c >= 1 ? 'hidden' : '';

      const w = ease(clamp((p - 0.44) / 0.44));
      const win = stage.style;
      win.setProperty('--win-y', `${((1 - w) * 72).toFixed(2)}vh`);
      win.setProperty('--win-s', (0.9 + 0.1 * w).toFixed(4));
      win.setProperty('--win-o', clamp(w * 2.2).toFixed(3));
    };

    const schedule = () => { if (!ticking) { ticking = true; requestAnimationFrame(render); } };

    const setMode = () => {
      if (reduceMotion.matches) {
        hero.setAttribute('data-static', '');
        removeEventListener('scroll', schedule);
        return;
      }
      hero.removeAttribute('data-static');
      geo = null;
      addEventListener('scroll', schedule, { passive: true });
      render();
    };
    addEventListener('resize', () => { geo = null; schedule(); });
    reduceMotion.addEventListener('change', setMode);
    document.fonts?.ready.then(() => { geo = null; schedule(); });
    setMode();
  }

  // ---------- Reveal on scroll ----------

  const reveals = $$('[data-reveal]');
  if ('IntersectionObserver' in window) {
    // Siblings that enter together arrive in sequence.
    reveals.forEach((el) => {
      const sibs = [...el.parentElement.children].filter((c) => c.hasAttribute('data-reveal'));
      const i = sibs.indexOf(el);
      if (i > 0) el.style.setProperty('--d', `${Math.min(i, 5) * 0.08}s`);
    });
    const io = new IntersectionObserver((entries) => {
      for (const e of entries) if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.12 });
    reveals.forEach((el) => io.observe(el));
  } else {
    reveals.forEach((el) => el.classList.add('in'));
  }

  // ---------- Feature tour ----------

  const steps = $$('.tour-step');
  if (steps.length) {
    // Small screens show each step's shot inline, on its own print.
    steps.forEach((step) => {
      const key = step.dataset.step;
      const inline = $('.tour-inline', step);
      const shot = $(`.tour-shot[data-shot="${key}"] picture`);
      const print = $(`.tour-print[data-print="${key}"]`);
      if (inline && shot) {
        inline.append(shot.cloneNode(true));
        $('img', inline)?.setAttribute('loading', 'lazy');
        inline.style.backgroundImage = print.style.backgroundImage;
      }
    });
    const activate = (key) => {
      steps.forEach((s) => s.classList.toggle('is-active', s.dataset.step === key));
      $$('.tour-print').forEach((el) => el.classList.toggle('is-active', el.dataset.print === key));
      $$('.tour-shot').forEach((el) => el.classList.toggle('is-active', el.dataset.shot === key));
    };
    activate(steps[0].dataset.step);
    const io = new IntersectionObserver((entries) => {
      for (const e of entries) if (e.isIntersecting) activate(e.target.dataset.step);
    }, { rootMargin: '-48% 0px -48% 0px' });
    steps.forEach((s) => io.observe(s));
  }

  // ---------- Icon picker ----------
  //
  // Mirrors Settings ▸ Appearance ▸ App Icon. The choice also re-prints this page:
  // the mark in the header, the hero's print and the favicon follow it.

  const picker = $('[data-icon-picker]');
  if (picker) {
    const buttons = $$('button', picker);
    const preview = $('[data-icon-preview]');
    const backdrop = $('[data-icon-backdrop]');
    const heroPrint = $('[data-hero-print]');
    const favicon = $('#favicon');
    const brandIcon = $('[data-brand-icon]');

    const iconSrc = (name) => `assets/icons/${name}${darkScheme.matches ? '-dark' : ''}.webp`;
    const paint = () => buttons.forEach((b) => { $('img', b).src = iconSrc(b.dataset.icon); });

    const choose = (button, { persist = true } = {}) => {
      const name = button.dataset.icon;
      const print = button.dataset.print;
      buttons.forEach((b) => {
        const on = b === button;
        b.setAttribute('aria-checked', String(on));
        b.tabIndex = on ? 0 : -1;
      });
      preview.src = iconSrc(name);
      preview.alt = `Room’s icon, the ${button.textContent.trim()} print.`;
      backdrop.style.backgroundImage = `url(assets/art/${print}-1536.avif)`;
      if (heroPrint) heroPrint.style.backgroundImage = `url(assets/art/${print}-1536.avif)`;
      $$('.mark').forEach((m) => { m.style.backgroundImage = `url(assets/icons/${name}-glyph.webp)`; });
      if (favicon) { favicon.href = `assets/icons/${name}.webp`; favicon.type = 'image/webp'; }
      if (brandIcon) { brandIcon.href = `assets/icons/${name}.webp`; brandIcon.download = `room-icon-${name}.webp`; }
      if (persist) store.set('room.icon', name);
    };

    buttons.forEach((b) => b.addEventListener('click', () => choose(b)));
    picker.addEventListener('keydown', (e) => {
      const keys = { ArrowRight: 1, ArrowDown: 4, ArrowLeft: -1, ArrowUp: -4 };
      if (!(e.key in keys)) return;
      e.preventDefault();
      const i = buttons.findIndex((b) => b.getAttribute('aria-checked') === 'true');
      const next = buttons[(i + keys[e.key] + buttons.length) % buttons.length];
      choose(next);
      next.focus();
    });
    darkScheme.addEventListener('change', () => {
      paint();
      const current = buttons.find((b) => b.getAttribute('aria-checked') === 'true');
      if (current) preview.src = iconSrc(current.dataset.icon);
    });
    paint();
    const saved = buttons.find((b) => b.dataset.icon === store.get('room.icon'));
    choose(saved || buttons[0], { persist: false });
  }

  // ---------- Brand menu: right-click (or long-press) the header mark ----------

  const brand = $('[data-brand]');
  const menu = $('[data-brand-menu]');
  if (brand && menu) {
    const toast = (text) => {
      const t = document.createElement('div');
      t.className = 'toast';
      t.setAttribute('role', 'status');
      t.textContent = text;
      document.body.append(t);
      setTimeout(() => t.remove(), 2300);
    };
    const close = () => { menu.hidden = true; };
    const open = (x, y) => {
      menu.hidden = false;
      const r = menu.getBoundingClientRect();
      menu.style.left = `${Math.min(x, innerWidth - r.width - 12)}px`;
      menu.style.top = `${Math.min(y, innerHeight - r.height - 12)}px`;
      $('[role="menuitem"]', menu).focus({ preventScroll: true });
    };
    brand.addEventListener('contextmenu', (e) => { e.preventDefault(); open(e.clientX, e.clientY); });
    let press;
    brand.addEventListener('touchstart', (e) => {
      const t = e.touches[0];
      press = setTimeout(() => open(t.clientX, t.clientY), 550);
    }, { passive: true });
    brand.addEventListener('touchend', () => clearTimeout(press));
    addEventListener('pointerdown', (e) => { if (!menu.hidden && !menu.contains(e.target)) close(); });
    addEventListener('keydown', (e) => { if (e.key === 'Escape') close(); });
    addEventListener('scroll', () => { if (!menu.hidden) close(); }, { passive: true });
    menu.addEventListener('click', async (e) => {
      const el = e.target.closest('[data-brand-action]');
      if (!el) { if (e.target.closest('a')) close(); return; }
      try {
        if (el.dataset.brandAction === 'copy-svg') {
          const svg = await (await fetch('assets/mark.svg')).text();
          await navigator.clipboard.writeText(svg);
          toast('Mark copied as SVG');
        } else if (el.dataset.brandAction === 'copy-color') {
          await navigator.clipboard.writeText(el.dataset.color.toUpperCase());
          toast(`${el.dataset.color.toUpperCase()} copied`);
        }
      } catch {
        toast('Copy is not available here');
      }
      close();
    });
  }
})();
