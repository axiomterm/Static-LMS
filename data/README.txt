Data folder — OUTSIDE the web root (not published to IIS).

This folder only holds schema.sql: the SQL Server schema script for this
project. There is no local database file — the app connects directly to a
SQL Server instance configured in wwwroot/web.config (<connectionStrings>
name="Training").

Setup:
  1. Provision a SQL Server database (local or remote).
  2. Run schema.sql once against it to create the tables.
  3. Set the connection string in wwwroot/web.config.

schema.sql is kept here (outside wwwroot) so it can't be downloaded from
the published site.
