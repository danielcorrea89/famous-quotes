-- master DB (no-op for contained user, but safe)
-- then run in db-famousquotes-dev:
CREATE USER [app-famousquotes-dev] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [app-famousquotes-dev];
ALTER ROLE db_datawriter ADD MEMBER [app-famousquotes-dev];
ALTER ROLE db_ddladmin ADD MEMBER [app-famousquotes-dev];