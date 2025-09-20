using Microsoft.Data.SqlClient;

namespace FamousQuotes.Api.Data;

public static class DbInitializer
{
    public static async Task EnsureTableExistsAsync(SqlConnection conn, CancellationToken ct)
    {
        var sql = @"
IF NOT EXISTS (
    SELECT 1
    FROM sys.tables
    WHERE name = 'Quotes' AND schema_id = SCHEMA_ID('dbo')
)
BEGIN
    CREATE TABLE dbo.Quotes (
        Id INT IDENTITY(1,1) PRIMARY KEY,
        [Text] NVARCHAR(1000) NOT NULL,
        Author NVARCHAR(200) NULL,
        [Source] NVARCHAR(200) NULL,
        CreatedAt DATETIME2 NOT NULL CONSTRAINT DF_Quotes_CreatedAt DEFAULT SYSUTCDATETIME()
    );
END";
        await using var cmd = new SqlCommand(sql, conn);
        await cmd.ExecuteNonQueryAsync(ct);
    }
}