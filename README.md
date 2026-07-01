# Internal Training Portal

Course site for internal use. Courses are written in Markdown
(`content/*.md`), a **PowerShell 7** script compiles them to static HTML
(`wwwroot/`), and they're published on **IIS** with Integrated Windows
Authentication (SSO against Active Directory). Styled with **Bootstrap**.

The course catalog is **100% static**. Two optional features use **ASP.NET
(Web Forms) + SQL Server**: the **access log** and the **course completion
status**.

## Quick guide

**Add a course**
1. Create `content/<id>.md` with its front matter (`title`, `description`, `date` and, if applicable, `categories`, `video`, `documents`).
2. If it has video/documents, put them in `wwwroot/assets/<id>/`.
3. Build: `pwsh -File .\build.ps1`
4. Publish the contents of `wwwroot/`.

**Add a category**
1. Add `"slug": "Display name"` to `content/categories.json` (the *slug* in lowercase, no accents or spaces).
2. Use it in courses: `categories: [slug]` in their front matter.
3. Build: `pwsh -File .\build.ps1` (the category will appear in the index filter).
4. Publish the contents of `wwwroot/`.

> Current categories are defined in [content/categories.json](content/categories.json)
> (Onboarding, Training — just examples; extend this file with your organization's
> real categories).

## Structure

```
utic_formacion/
├─ content/                 Sources (NOT published to IIS)
│  ├─ welcome.md
│  └─ categories.json       Controlled vocabulary of categories
├─ build/
│  └─ templates/            HTML templates (index.html, course.html)
├─ build.ps1                Generator (PowerShell 7+)
├─ data/                    ←—— OUTSIDE the web root. Do NOT publish to IIS
│  ├─ schema.sql            SQL Server schema (run once to provision the database)
│  └─ README.txt
└─ wwwroot/                 ←—— THIS is what gets published to IIS
   ├─ index.html            (generated)
   ├─ courses/*.html        (generated)
   ├─ web.config            Windows Auth + SQL Server connection string + video MIME + cache
   ├─ App_Code/
   │  └─ Db.cs              Shared DB + request helpers (auto-compiled by IIS)
   ├─ api/                  ASP.NET endpoints (access.aspx, completion.aspx)
   └─ assets/
      ├─ css/               bootstrap.min.css
      ├─ js/                filters.js, access.js, completion.js
      └─ <course-id>/       videos, PDFs and images for each course
```

> **Important:** `content/`, `build/` and `data/` stay **outside** the directory
> published by IIS (`wwwroot`). This way nobody can download the original
> `.md` files, the templates, or the schema script. (`App_Code` is a protected
> ASP.NET folder — its source is never served either.)

## Adding or editing a course

1. Create `content/<id>.md` with its front matter (see below).
2. If the course has video/documents, create `wwwroot/assets/<id>/` and put the
   files there.
3. Run the build:
   ```powershell
   pwsh -File .\build.ps1
   ```
4. Publish the contents of `wwwroot/` to the server.

### Front matter (the .md header)

```yaml
---
id: my-course                        # optional (defaults to the file name)
title: My course title
description: Short summary for the catalog.
date: 2026-06-12                     # YYYY-MM-DD; sorts the catalog (newest first)
categories: [onboarding, training]    # optional; slugs from content/categories.json
video: assets/my-course/intro.mp4    # optional
documents:                           # optional
  - assets/my-course/manual.pdf
  - assets/my-course/checklist.pdf
---

The course content goes here in regular **Markdown**
(headings, lists, tables, quotes, code, links, images...).
```

- The **paths** for `video` and `documents` are relative to the site root
  (`wwwroot`), e.g. `assets/<id>/file.ext`.
- Recognized video formats: `.mp4`, `.webm`, `.ogv`.
- The body supports full Markdown, including **tables** and strikethrough (GFM).
- `categories` accepts an inline list `[a, b]` or a block list (`- a` per line).

## Categories

To avoid duplicates (e.g. *Mobile* vs *Mobility*), categories use a
**controlled vocabulary**: the master file [content/categories.json](content/categories.json)
maps each `slug` to its display name and defines the order:

```json
{
  "onboarding": "Onboarding",
  "training":   "Training"
}
```

- Each course references categories **by slug** in `categories:`.
- The build **validates** slugs against the master list. If one doesn't exist:
  - by default it **warns** and skips that chip;
  - with `pwsh -File .\build.ps1 -Strict` the build **fails** (useful in CI/publishing).
- The index shows a **filter box** with a **category dropdown**
  (checkboxes; **all** categories from the master list, in their order). It's
  **multi-select with OR logic**: checking several shows courses that have
  **at least one** of them. To remove a filter, uncheck its box. If a
  category has no courses, checking it shows "No courses match the selection."
- Next to the dropdown there's a **Sort** control: toggles between **Date**
  (newest first, default) and **Alphabetical (A-Z)**. It reorders the catalog
  on the client (no reload) and works alongside the category filter.

To add a new category: edit `categories.json` once and reference it by its slug.

## Access log

- When a course is opened, `access.js` calls `wwwroot/api/access.aspx`, which logs
  **user + course + date (UTC) + IP + user-agent**.
- The user is provided by IIS (Windows Auth) via `LOGON_USER`; the client only
  sends the course id.

## Course completion status

- On each course page, `completion.js` shows the **"Mark as completed"** button,
  which toggles the state directly on click. The state is saved per AD user via
  `wwwroot/api/completion.aspx` (table `course_completions`).
- A row in `course_completions` exists **only** if the user completed the course;
  unmarking deletes it. The GET returns the plain list of completed course ids.
- On the **index**, each card reflects the state: a **green stripe + ✓** if
  you've completed it.
- The **"Courses"** filter on the index lets you view: **All**, **Pending**, or
  **Completed**.
- Since the pages are static, the per-user state is filled in **with JS on
  load**; without JS or ASP.NET, the pages still display but without these extras.

## Database (SQL Server)

- Data access lives in [wwwroot/App_Code/Db.cs](wwwroot/App_Code/Db.cs), which
  opens a `System.Data.SqlClient` connection using the `Training` connection
  string in [wwwroot/web.config](wwwroot/web.config).
- Set that connection string for your SQL Server instance and run
  [data/schema.sql](data/schema.sql) once to create the tables. The endpoints
  need no further changes.
- **Privacy:** the access log contains personal data. Define a **retention**
  policy (e.g. purging `course_accesses` after N months) per your regulations.

## Deploying to IIS

1. Copy the **contents of `wwwroot/`** to the site's physical folder
   (or point the site at that folder). Don't upload `content/`, `build/` or `data/`.
2. Provision a **SQL Server** database (local or remote) and run
   [data/schema.sql](data/schema.sql) once against it. Set the `Training`
   connection string in `wwwroot/web.config`.
3. In **IIS Manager**, on the site → *Authentication*:
   - **Enable** "Windows Authentication".
   - **Disable** "Anonymous Authentication".
   *(The "Windows Authentication" feature must be installed in the IIS role;
   if it's not listed, install it from "Add Roles and Features").*
4. The endpoints are classic **ASP.NET Web Forms** pages (`.aspx` + `App_Code`) —
   no build step, IIS compiles them on the fly. The site's **Application Pool**
   must target **.NET CLR v4.0** (Integrated pipeline). The App Pool identity
   needs access to the SQL Server database (or use SQL auth in the connection
   string).
5. Use **HTTPS**. Windows Authentication over HTTP exposes credentials/tokens.
6. The included `web.config` already enables Windows mode, denies anonymous
   users, defines video MIME types, disables directory listing, and hides error
   details from remote clients.

On domain-joined machines, the user logs in **without typing a password** (SSO).

## Requirements

- **Build:** PowerShell 7+ (uses `ConvertFrom-Markdown`). Check with
  `$PSVersionTable.PSVersion`.
- **Server:** IIS with the *Windows Authentication* module and **ASP.NET 4.x**
  (.NET Framework) enabled.
- **Only for the access log and completion status:** a reachable SQL Server
  instance (the course catalog works without ASP.NET or the database).

## Notes

- Bootstrap is served **locally** (`assets/css/bootstrap.min.css`,
  `assets/js/bootstrap.bundle.min.js`), no CDN.
- `assets/<id>/README.txt` is a placeholder marker; delete it once you add the
  real resources.
- Since the authors are internal and trusted, embedded HTML is allowed inside
  the Markdown (e.g. for custom embeds).

## Ideas for later

- An internal page to **review access log results** (an ASP.NET report or a
  CSV/Excel export).
- Show per-user progress based on the completion status.
