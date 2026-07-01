-- Database schema for SQL Server. Run this once when provisioning the database.
-- The endpoint queries (parameterized INSERT/DELETE/SELECT) work as-is with
-- System.Data.SqlClient from App_Code/Db.cs.

CREATE TABLE course_accesses (
    id           INT IDENTITY(1,1) PRIMARY KEY,
    username     NVARCHAR(256) NOT NULL,
    course_id    NVARCHAR(128) NOT NULL,
    accessed_utc DATETIME2     NOT NULL,
    ip           NVARCHAR(64)  NULL,
    user_agent   NVARCHAR(256) NULL
);
CREATE INDEX ix_course_accesses_course ON course_accesses (course_id);
CREATE INDEX ix_course_accesses_user   ON course_accesses (username);

-- A row exists only if the user completed the course (uncomplete deletes it).
CREATE TABLE course_completions (
    username      NVARCHAR(256) NOT NULL,
    course_id     NVARCHAR(128) NOT NULL,
    completed_utc DATETIME2     NOT NULL,
    CONSTRAINT pk_course_completions PRIMARY KEY (username, course_id)
);
