using System;
using System.Data.SqlClient;
using System.Text.RegularExpressions;
using System.Web;
using System.Web.Script.Serialization;

/// <summary>
/// Shared data access + request helpers (the old db.php).
/// The connection string lives in web.config under &lt;connectionStrings name="Training"&gt;.
/// Files in App_Code are compiled automatically by IIS — no project, no build step.
/// </summary>
public static class Db
{
    /// <summary>Opens a SQL Server connection. The schema is created beforehand with data/schema.sql.</summary>
    public static SqlConnection Open()
    {
        var cs = System.Configuration.ConfigurationManager.ConnectionStrings["Training"].ConnectionString;
        var conn = new SqlConnection(cs);
        conn.Open();
        return conn;
    }

    /// <summary>User authenticated by IIS (Windows Auth). Returns "DOMAIN\user", or "unknown".</summary>
    public static string CurrentUser()
    {
        var u = HttpContext.Current.Request.ServerVariables["LOGON_USER"];
        return string.IsNullOrEmpty(u) ? "unknown" : u;
    }

    /// <summary>
    /// Lightweight CSRF defense: if the browser sends Origin/Referer, its host must match ours.
    /// If it doesn't send them, it's allowed (e.g. beacons).
    /// </summary>
    public static bool SameOrigin()
    {
        var req = HttpContext.Current.Request;
        foreach (var key in new[] { "Origin", "Referer" })
        {
            var val = req.Headers[key];
            Uri u;
            if (!string.IsNullOrEmpty(val) && Uri.TryCreate(val, UriKind.Absolute, out u)
                && !string.Equals(u.Host, req.Url.Host, StringComparison.OrdinalIgnoreCase))
                return false;
        }
        return true;
    }

    /// <summary>Reads and validates course_id from the request; responds 400 and stops if invalid.</summary>
    public static string ReadCourseId()
    {
        var c = (HttpContext.Current.Request["course_id"] ?? "").Trim();
        if (c.Length == 0 || !Regex.IsMatch(c, @"^[A-Za-z0-9_-]{1,128}$"))
            Respond(400, new { error = "Invalid course_id" });
        return c;
    }

    /// <summary>Writes JSON and ends the request (like PHP's respond()).</summary>
    public static void Respond(int code, object payload)
    {
        var res = HttpContext.Current.Response;
        res.Clear();
        res.StatusCode = code;
        res.ContentType = "application/json; charset=utf-8";
        res.Write(new JavaScriptSerializer().Serialize(payload));
        res.End();
    }
}
