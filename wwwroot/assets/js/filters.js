// Index: filters (category + completed) and sort (Date / Alphabetical).
(function () {
  document.addEventListener('DOMContentLoaded', function () {
    initFilters();
    initSort();
  });

  // --- Combined filters: category (OR) AND completed status ---
  function initFilters() {
    var grid = document.querySelector('.courses-grid');
    if (!grid) return;
    var cards = Array.prototype.slice.call(grid.querySelectorAll('.course-item'));
    var empty = document.querySelector('.no-results');

    var dropdown = document.querySelector('.category-filter');
    var checks = dropdown ? Array.prototype.slice.call(dropdown.querySelectorAll('input[type=checkbox]')) : [];
    var toggle = dropdown ? dropdown.querySelector('.dropdown-toggle') : null;
    var base = toggle ? (toggle.getAttribute('data-base') || toggle.textContent.trim()) : '';

    var courseSel = document.querySelector('.course-filter');

    function apply() {
      var cats = checks.filter(function (c) { return c.checked; }).map(function (c) { return c.value; });
      if (toggle) toggle.textContent = cats.length ? base + ' (' + cats.length + ')' : base;
      var mode = courseSel ? courseSel.value : 'all';
      var visible = 0;
      cards.forEach(function (t) {
        var ok = true;
        if (cats.length) {
          var tc = (t.getAttribute('data-categories') || '').split(/\s+/);
          ok = cats.some(function (x) { return tc.indexOf(x) !== -1; });
        }
        if (ok && mode !== 'all') {
          if (mode === 'completed') ok = t.classList.contains('completed');
          else if (mode === 'pending') ok = !t.classList.contains('completed');
        }
        t.hidden = !ok;
        if (ok) visible++;
      });
      if (empty) empty.hidden = visible !== 0;
    }

    checks.forEach(function (c) { c.addEventListener('change', apply); });
    if (courseSel) courseSel.addEventListener('change', apply);
    // completion.js marks the cards asynchronously: re-apply once it's done
    document.addEventListener('completions-ready', apply);
  }

  // --- Catalog sort ---
  function initSort() {
    var sel = document.querySelector('.course-sort');
    var grid = document.querySelector('.courses-grid');
    if (!sel || !grid) return;

    function title(art) {
      var s = art.querySelector('.card-header h2') || art.querySelector('.card-header');
      return s ? s.textContent.trim() : '';
    }

    function sort() {
      var items = Array.prototype.slice.call(grid.querySelectorAll('.course-item'));
      var alphabetical = sel.value === 'alphabetical';
      items.sort(function (a, b) {
        if (alphabetical) {
          return title(a).localeCompare(title(b), 'es', { sensitivity: 'base' });
        }
        var da = a.getAttribute('data-date') || '';
        var db = b.getAttribute('data-date') || '';
        if (da === db) return title(a).localeCompare(title(b), 'es', { sensitivity: 'base' });
        return da < db ? 1 : -1; // descending date (newest first)
      });
      items.forEach(function (a) { grid.appendChild(a); });
    }

    sel.addEventListener('change', sort);
    sort();
  }
})();
