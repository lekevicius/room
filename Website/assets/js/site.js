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

  // ---------- Shortcuts: the run twice, so the loop has no end ----------

  const marquee = $('[data-marquee]');
  if (marquee && !reduceMotion.matches) marquee.append(...[...marquee.children].map((c) => c.cloneNode(true)));

  // ---------- Nav: arrives once the name has scrolled away ----------

  const nav = $('[data-nav]');
  const heroTitle = $('[data-hero-title]');
  if (nav && heroTitle && 'IntersectionObserver' in window) {
    new IntersectionObserver(([e]) => {
      nav.dataset.hidden = String(e.isIntersecting || e.boundingClientRect.top > 0);
    }, { threshold: 0 }).observe(heroTitle);
  } else if (nav) {
    nav.dataset.hidden = 'false';
  }

  // ---------- The letter's video: shown once it exists ----------

  const letterVideo = $('[data-letter-video]');
  if (letterVideo) {
    fetch(letterVideo.dataset.src, { method: 'HEAD' }).then((r) => {
      if (!r.ok) return;
      const frame = $('.letter-video-frame', letterVideo);
      const video = document.createElement('video');
      Object.assign(video, { src: letterVideo.dataset.src, controls: true, playsInline: true, preload: 'metadata' });
      frame.replaceChildren(video);
    }).catch(() => {});
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

  // ---------- Clips: recorded with Website/capture/record.sh ----------
  //
  // A clip is the window alone, without the system cursor, plus the pointer's track.
  // The cursor is drawn here, on the video's own frames, so it stays sharp at any size.

  const CURSOR = '<svg class="cursor-arrow" viewBox="0 0 20 28" aria-hidden="true"><path d="M2.2 1.6v21.2l5.1-4.9 3.3 7.6 3.5-1.5-3.3-7.5h7.1z" fill="#111" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>';

  const mountClip = (figure, name) => {
    const box = document.createElement('div');
    box.className = 'clip';
    const video = document.createElement('video');
    Object.assign(video, { muted: true, loop: true, playsInline: true, preload: 'metadata' });
    video.setAttribute('muted', '');
    video.poster = `assets/clips/${name}.webp`;
    video.src = `assets/clips/${name}.mp4`;
    const cursor = document.createElement('div');
    cursor.className = 'cursor';
    cursor.innerHTML = CURSOR;
    box.append(video, cursor);
    figure.querySelector('picture')?.replaceWith(box);
    figure.classList.add('has-clip');

    // Keyboard-led clips have no pointer track, and then no cursor.
    let track = null;
    cursor.hidden = true;
    fetch(`assets/clips/${name}.cursor.json`).then((r) => (r.ok ? r.json() : null)).then((t) => {
      if (t && t.events && t.events.length) { track = t; cursor.hidden = reduceMotion.matches; }
    }).catch(() => {});
    new ResizeObserver(([e]) => {
      if (track) box.style.setProperty('--k', (e.contentRect.width / track.width).toFixed(4));
    }).observe(box);

    let lastDown = -1;
    const at = (time) => {
      const ev = track.events;
      let lo = 0, hi = ev.length - 1;
      while (lo < hi) { const mid = (lo + hi + 1) >> 1; if (ev[mid][0] <= time) lo = mid; else hi = mid - 1; }
      const a = ev[lo], b = ev[Math.min(lo + 1, ev.length - 1)];
      const f = b[0] > a[0] ? clamp((time - a[0]) / (b[0] - a[0])) : 0;
      // Pressed from a down until the next up.
      let pressed = false;
      for (let i = lo; i >= 0; i--) { if (ev[i][3] === 'u') break; if (ev[i][3] === 'd') { pressed = true; break; } }
      let down = -1;
      for (let i = lo; i >= 0 && time - ev[i][0] < 0.5; i--) if (ev[i][3] === 'd') { down = ev[i][0]; break; }
      return { x: a[1] + (b[1] - a[1]) * f, y: a[2] + (b[2] - a[2]) * f, pressed, down };
    };
    const ring = (x, y) => {
      const r = document.createElement('span');
      r.className = 'click-ring';
      r.style.left = `${(x / track.width) * 100}%`;
      r.style.top = `${(y / track.height) * 100}%`;
      box.append(r);
      r.addEventListener('animationend', () => r.remove());
    };
    const frame = () => {
      if (track && track.events.length) {
        const p = at(video.currentTime);
        cursor.style.left = `${(p.x / track.width) * 100}%`;
        cursor.style.top = `${(p.y / track.height) * 100}%`;
        cursor.classList.toggle('is-pressed', p.pressed);
        if (p.down >= 0 && p.down !== lastDown) { lastDown = p.down; ring(p.x, p.y); }
        if (video.currentTime < 0.05) lastDown = -1;
      }
      schedule();
    };
    const schedule = () => {
      if ('requestVideoFrameCallback' in video) video.requestVideoFrameCallback(frame);
      else requestAnimationFrame(frame);
    };
    schedule();

    if (reduceMotion.matches) { cursor.hidden = true; return video; }
    const io = new IntersectionObserver(([e]) => {
      const active = !figure.classList.contains('tour-shot') || figure.classList.contains('is-active');
      if (e.isIntersecting && active) video.play().catch(() => {}); else video.pause();
    }, { threshold: 0.4 });
    io.observe(figure);
    new MutationObserver(() => {
      if (figure.classList.contains('is-active')) { video.currentTime = 0; video.play().catch(() => {}); } else video.pause();
    }).observe(figure, { attributes: true, attributeFilter: ['class'] });
    return video;
  };

  fetch('assets/clips/clips.json').then((r) => (r.ok ? r.json() : [])).then((clips) => {
    const scheme = darkScheme.matches ? 'dark' : 'light';
    $$('[data-shot]').forEach((figure) => {
      const key = figure.dataset.shot;
      const name = clips.includes(`${key}-${scheme}`) ? `${key}-${scheme}` : clips.includes(`${key}-light`) ? `${key}-light` : null;
      if (name) mountClip(figure, name);
    });
  }).catch(() => {});

  // ---------- Icon picker: a cycle ----------
  //
  // Mirrors Settings ▸ Appearance ▸ App Icon. The chosen icon sits in the middle on its print,
  // its neighbours either side, wrapping around. The choice also re-prints this page: the mark
  // in the header, the hero's print and the favicon follow it.

  const picker = $('[data-icon-picker]');
  if (picker) {
    const buttons = $$('button', picker);
    const backdrop = $('[data-icon-backdrop]');
    const backdropNext = $('[data-icon-backdrop-next]');
    const nameLabel = $('[data-icon-name]');
    const favicon = $('#favicon');
    const brandIcon = $('[data-brand-icon]');
    const count = buttons.length;
    let current = 0;

    const iconSrc = (name) => `assets/icons/${name}${darkScheme.matches ? '-dark' : ''}.webp`;
    const paint = () => buttons.forEach((b) => { $('img', b).src = iconSrc(b.dataset.icon); });

    const layout = () => {
      buttons.forEach((b, i) => {
        // The shortest way round: offsets -3…3 for seven icons.
        let o = ((i - current) % count + count) % count;
        if (o > count / 2) o -= count;
        const before = Number(b.style.getPropertyValue('--o') || o);
        // An icon wrapping from one end to the other jumps over unseen and fades in there,
        // rather than flying across the stage.
        if (Math.abs(o - before) > count / 2) {
          b.classList.add('is-wrapping');
          b.style.setProperty('--o', o);
          b.style.setProperty('--a', Math.abs(o));
          void b.offsetWidth;
          requestAnimationFrame(() => b.classList.remove('is-wrapping'));
        } else {
          b.style.setProperty('--o', o);
          b.style.setProperty('--a', Math.abs(o));
        }
        b.style.visibility = Math.abs(o) > 3 ? 'hidden' : '';
      });
    };

    const choose = (index, { persist = true } = {}) => {
      current = (index + count) % count;
      const button = buttons[current];
      const name = button.dataset.icon;
      const print = button.dataset.print;
      buttons.forEach((b, i) => {
        b.setAttribute('aria-checked', String(i === current));
        b.tabIndex = i === current ? 0 : -1;
      });
      layout();
      nameLabel.textContent = button.getAttribute('aria-label');
      // The next print fades in over the current one, then takes its place.
      const url = `url("assets/art/${print}-1536.avif")`;
      if (backdrop.style.backgroundImage !== url) {
        const preload = new Image();
        preload.onload = () => {
          backdropNext.style.backgroundImage = url;
          backdropNext.classList.remove('is-next');
          clearTimeout(backdropNext.swap);
          backdropNext.swap = setTimeout(() => {
            backdrop.style.backgroundImage = url;
            backdropNext.style.transition = 'none';
            backdropNext.classList.add('is-next');
            void backdropNext.offsetWidth;
            backdropNext.style.transition = '';
          }, 820);
        };
        preload.src = `assets/art/${print}-1536.avif`;
      }
      $$('.mark').forEach((m) => { m.style.backgroundImage = `url(assets/icons/${name}-glyph.webp)`; });
      $$('[data-room-icon]').forEach((img) => { img.src = iconSrc(name); });
      if (favicon) { favicon.href = `assets/icons/${name}.webp`; favicon.type = 'image/webp'; }
      if (brandIcon) { brandIcon.href = `assets/icons/${name}.webp`; brandIcon.download = `room-icon-${name}.webp`; }
      if (persist) store.set('room.icon', name);
    };

    buttons.forEach((b, i) => b.addEventListener('click', () => choose(i)));
    $$('[data-step-by]').forEach((b) => b.addEventListener('click', () => choose(current + Number(b.dataset.stepBy))));
    picker.addEventListener('keydown', (e) => {
      const keys = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 };
      if (!(e.key in keys)) return;
      e.preventDefault();
      choose(current + keys[e.key]);
      buttons[current].focus();
    });
    darkScheme.addEventListener('change', paint);
    paint();
    const saved = buttons.findIndex((b) => b.dataset.icon === store.get('room.icon'));
    choose(saved >= 0 ? saved : 0, { persist: false });
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
