// Completed status (via api/completion.aspx).
// Works in 2 contexts: course page (complete button) and index (stripe + icon).
// The API returns { completed: [course_id, ...], user }: a course id is present
// only if it's completed.
(function () {
  var COMPLETED_ICON = '<span class="completed-icon text-success flex-shrink-0" title="Completed" role="img" aria-label="Completed"><svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/></svg></span>';

  document.addEventListener('DOMContentLoaded', function () {
    var metaCourse = document.querySelector('meta[name="course-id"]');
    var onCoursePage = !!metaCourse;
    var API = (onCoursePage ? '../' : '') + 'api/';

    fetch(API + 'completion.aspx', { credentials: 'same-origin' })
      .then(function (r) { return r.ok ? r.json() : { completed: [] }; })
      .then(function (data) {
        var done = {};
        (data.completed || []).forEach(function (id) { done[id] = true; });
        if (onCoursePage) initCourse(metaCourse.getAttribute('content'), done, API);
        decorateIndex(done);
        showUser(data.user);
        document.dispatchEvent(new CustomEvent('completions-ready'));
      })
      .catch(function () { /* silent */ });
  });

  function post(API, action, courseId) {
    var d = new FormData();
    d.append('action', action);
    d.append('course_id', courseId);
    return fetch(API + 'completion.aspx', { method: 'POST', body: d, credentials: 'same-origin' })
      .then(function (r) { if (!r.ok) throw new Error(); return r.json(); });
  }

  // --- Course page: complete button ---
  function initCourse(courseId, done, API) {
    var cont = document.querySelector('.course-actions');
    if (!cont) return;
    var btnComplete = cont.querySelector('.btn-complete');
    var state = { completed: !!done[courseId] };

    function render() {
      btnComplete.textContent = state.completed ? 'Unmark as completed' : 'Mark as completed';
      cont.hidden = false;
    }
    render();

    btnComplete.addEventListener('click', function () {
      var action = state.completed ? 'uncomplete' : 'complete';
      btnComplete.setAttribute('aria-busy', 'true');
      post(API, action, courseId).then(function () {
        state.completed = !state.completed;
        btnComplete.removeAttribute('aria-busy');
        render();
      }).catch(function () { btnComplete.removeAttribute('aria-busy'); });
    });
  }

  // --- Header: user name ---
  function showUser(user) {
    var name = (user || '').split('\\').pop().split('/').pop();
    if (!name) return;
    var nameEl = document.querySelector('.user-name');
    var headerEl = document.querySelector('.user-header');
    if (nameEl) nameEl.textContent = name;
    if (headerEl) headerEl.hidden = false;
  }

  // --- Index: green border + icon in the header if completed ---
  function decorateIndex(done) {
    var cards = document.querySelectorAll('.courses-grid .course-item[data-course-id]');
    Array.prototype.forEach.call(cards, function (t) {
      if (done[t.getAttribute('data-course-id')]) markCard(t);
    });
  }

  function markCard(item) {
    item.classList.add('completed');
    var card = item.querySelector('.card');
    if (card) card.classList.add('border-start', 'border-success', 'border-3');
    var header = item.querySelector('.card-header');
    if (header && !header.querySelector('.completed-icon')) {
      header.insertAdjacentHTML('beforeend', COMPLETED_ICON);
    }
  }

})();
