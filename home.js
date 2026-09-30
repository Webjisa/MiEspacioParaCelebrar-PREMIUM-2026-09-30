(() => {
  const FALLBACK_HERO = 'assets/7c24953f-0f92-43e4-9c18-c534940cba2e.jpg';
  const state = { slides: [], index: 0, timer: null, paused: false };
  const escHome = value => String(value ?? '').replace(/[&<>'"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));

  function buildSlides(spaces) {
    const usable = (spaces || []).filter(s => s && s.image).map(s => ({
      id: s.id,
      name: s.name,
      image: s.image,
      city: s.city || 'Lucena'
    }));
    return usable.length ? usable : [{id:'fallback',name:'MiEspacioParaCelebrar',image:FALLBACK_HERO,city:'Lucena'}];
  }

  function renderSlides() {
    const root = document.querySelector('#homeHeroSlides');
    const dots = document.querySelector('#homeHeroDots');
    if (!root || !dots) return;
    root.innerHTML = state.slides.map((s,i) => `<div class="premium-hero-slide ${i===state.index?'is-active':''}" data-slide="${i}"><img src="${escHome(s.image)}" alt="${escHome(s.name)}"><span class="premium-slide-caption">${escHome(s.name)}</span></div>`).join('');
    dots.innerHTML = state.slides.map((s,i) => `<button type="button" class="premium-hero-dot ${i===state.index?'is-active':''}" data-slide-dot="${i}" aria-label="Mostrar imagen ${i+1}${s.name ? `: ${escHome(s.name)}` : ''}"></button>`).join('');
    dots.querySelectorAll('[data-slide-dot]').forEach(btn => btn.addEventListener('click', () => goTo(Number(btn.dataset.slideDot), true)));
  }

  function applyIndex() {
    document.querySelectorAll('.premium-hero-slide').forEach((el,i) => el.classList.toggle('is-active', i===state.index));
    document.querySelectorAll('.premium-hero-dot').forEach((el,i) => el.classList.toggle('is-active', i===state.index));
  }

  function goTo(index, userAction=false) {
    if (!state.slides.length) return;
    state.index = (index + state.slides.length) % state.slides.length;
    applyIndex();
    if (userAction) restartTimer();
  }

  function restartTimer() {
    clearInterval(state.timer);
    if (state.slides.length < 2) return;
    state.timer = setInterval(() => { if (!state.paused) goTo(state.index + 1); }, 6500);
  }

  function initCarousel() {
    const hero = document.querySelector('.premium-hero');
    if (!hero) return;
    hero.querySelector('.premium-hero-prev')?.addEventListener('click', () => goTo(state.index - 1, true));
    hero.querySelector('.premium-hero-next')?.addEventListener('click', () => goTo(state.index + 1, true));
    hero.addEventListener('mouseenter', () => { state.paused = true; });
    hero.addEventListener('mouseleave', () => { state.paused = false; });
    hero.addEventListener('focusin', () => { state.paused = true; });
    hero.addEventListener('focusout', () => { state.paused = false; });
    renderSlides();
    restartTimer();
  }

  function fillSpaceSelect(spaces) {
    const select = document.querySelector('#homeSpace');
    if (!select) return;
    select.innerHTML = '<option value="">Todos los espacios</option>' + (spaces || []).map(s => `<option value="${escHome(s.id)}">${escHome(s.name)}</option>`).join('');
  }

  function initSearch() {
    const button = document.querySelector('#homeSearch');
    if (!button) return;
    button.addEventListener('click', () => {
      const space = document.querySelector('#homeSpace')?.value || '';
      const start = document.querySelector('#homeStart')?.value || '';
      const end = document.querySelector('#homeEnd')?.value || '';
      if (start && end && end < start) {
        alert('La fecha de fin no puede ser anterior a la fecha de inicio.');
        return;
      }
      const params = new URLSearchParams();
      if (space) params.set('space', space);
      if (start) params.set('start', start);
      if (end) params.set('end', end);
      location.href = `disponibilidad.html${params.toString() ? `?${params.toString()}` : ''}`;
    });
  }

  async function initHome() {
    let spaces = [];
    try {
      if (typeof getPublicSpaces === 'function') spaces = await getPublicSpaces();
    } catch (error) {
      console.warn('No se pudieron cargar los espacios para el carrusel:', error);
    }
    state.slides = buildSlides(spaces);
    fillSpaceSelect(spaces);
    initCarousel();
    initSearch();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', initHome);
  else initHome();
})();
