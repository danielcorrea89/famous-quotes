using Microsoft.Data.SqlClient;

namespace FamousQuotes.Api.Data;

public static class DbInitializer
{
    private const string CreateSql = """
    IF NOT EXISTS (
        SELECT 1
        FROM sys.tables
        WHERE name = 'Quotes' AND schema_id = SCHEMA_ID('dbo')
    )
    BEGIN
        CREATE TABLE dbo.Quotes (
            Id        INT IDENTITY(1,1) PRIMARY KEY,
            [Text]    NVARCHAR(1000) NOT NULL,
            Author    NVARCHAR(200)  NULL,
            [Source]  NVARCHAR(200)  NULL,
            CreatedAt DATETIME2      NOT NULL
                CONSTRAINT DF_Quotes_CreatedAt DEFAULT SYSUTCDATETIME()
        );
    END
    """;

    public static async Task EnsureQuotesTableAsync(SqlConnection conn, CancellationToken ct)
    {
        await using var cmd = new SqlCommand(CreateSql, conn);
        await cmd.ExecuteNonQueryAsync(ct);
    }
}