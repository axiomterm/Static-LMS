<%@ WebHandler Language="C#" Class="Completion" %>
using System;
using System.Collections.Generic;
using System.Web;

// "Completed" status per user and course.
//   GET                    -> { completed: [course_id, ...], user } for the user
//   POST action=complete   -> marks as completed (adds the row if missing)
//   POST action=uncomplete -> unmarks as completed (removes the row)
// A row exists only if the course is completed. The user comes from IIS (Windows Auth).
public class Completion : IHttpHandler
{
    public void ProcessRequest(HttpContext context)
    {
        var req = context.Request;
        string user = Db.CurrentUser();

        if (req.HttpMethod == "GET")
        {
            var completed = new List<string>();
            using (var conn = Db.Open())
            using (var cmd = conn.CreateCommand())
            {
                cmd.CommandText = "SELECT course_id FROM course_completions WHERE username = @u";
                cmd.Parameters.AddWithValue("@u", user);
                using (var r = cmd.ExecuteReader())
                    while (r.Read()) completed.Add(r.GetString(0));
            }
            Db.Respond(200, new { completed = completed, user = user });
        }

        if (req.HttpMethod != "POST") Db.Respond(405, new { error = "Method not allowed" });
        if (!Db.SameOrigin())         Db.Respond(403, new { error = "Origin not allowed" });

        string course = Db.ReadCourseId();
        string action = (req["action"] ?? "").Trim();
        if (action != "complete" && action != "uncomplete")
            Db.Respond(400, new { error = "Invalid action" });

        using (var conn = Db.Open())
        using (var cmd = conn.CreateCommand())
        {
            if (action == "complete")
            {
                // Idempotent insert (the button only toggles, so no double-complete in practice).
                cmd.CommandText =
                    "IF NOT EXISTS (SELECT 1 FROM course_completions WHERE username = @u AND course_id = @c) " +
                    "INSERT INTO course_completions (username, course_id, completed_utc) VALUES (@u, @c, @t)";
                cmd.Parameters.AddWithValue("@t", DateTime.UtcNow);
            }
            else
            {
                cmd.CommandText = "DELETE FROM course_completions WHERE username = @u AND course_id = @c";
            }
            cmd.Parameters.AddWithValue("@u", user);
            cmd.Parameters.AddWithValue("@c", course);
            cmd.ExecuteNonQuery();
        }
        Db.Respond(200, new { ok = true });
    }

    public bool IsReusable { get { return true; } }
}
