<%@ Page Language="C#" %>
<script runat="server">
// Logs a user's access to a course (user + course + time). Called from access.js.
void Page_Load(object sender, EventArgs e)
{
    if (Request.HttpMethod != "POST") Db.Respond(405, new { error = "Method not allowed" });
    if (!Db.SameOrigin())            Db.Respond(403, new { error = "Origin not allowed" });

    string course = Db.ReadCourseId();
    string ua = Request.UserAgent ?? "";
    if (ua.Length > 255) ua = ua.Substring(0, 255);

    using (var conn = Db.Open())
    using (var cmd = conn.CreateCommand())
    {
        cmd.CommandText = "INSERT INTO course_accesses (username, course_id, accessed_utc, ip, user_agent) " +
                          "VALUES (@u, @c, @t, @ip, @ua)";
        cmd.Parameters.AddWithValue("@u", Db.CurrentUser());
        cmd.Parameters.AddWithValue("@c", course);
        cmd.Parameters.AddWithValue("@t", DateTime.UtcNow);
        cmd.Parameters.AddWithValue("@ip", (object)Request.UserHostAddress ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@ua", ua);
        cmd.ExecuteNonQuery();
    }
    Db.Respond(200, new { ok = true });
}
</script>
