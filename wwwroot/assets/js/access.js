// Logs the course access when the page loads.
// The server determines the user (Windows Auth -> REMOTE_USER);
// here we only send the course id. This is "fire and forget".
(function () {
  var meta = document.querySelector('meta[name="course-id"]');
  if (!meta) return;
  var courseId = meta.getAttribute('content');
  if (!courseId) return;

  var data = new FormData();
  data.append('course_id', courseId);

  try {
    // credentials:'same-origin' + keepalive: ensures IIS gets the
    // integrated authentication and the request isn't canceled on navigation.
    fetch('../api/access.ashx', {
      method: 'POST',
      body: data,
      credentials: 'same-origin',
      keepalive: true
    }).catch(function () { /* silent: don't bother the user */ });
  } catch (e) { /* ignore */ }
})();
