namespace VacationPlanner.Services;

/// <summary>
/// Connection settings read from the same environment variables the Python sample uses: <c>SQL_SERVER</c> and
/// <c>SQL_DATABASE</c>, with either <c>SQL_USERNAME</c>/<c>SQL_PASSWORD</c> (SQL authentication) or the
/// <c>AZURE_CLIENT_ID</c>/<c>AZURE_CLIENT_SECRET</c>/<c>AZURE_TENANT_ID</c> service principal (Microsoft Entra token).
/// </summary>
public sealed record SqlOptions(string Server, string Database, string? User, string? Password, bool UseAzureCredential, string Username)
{
    public static SqlOptions FromEnvironment()
    {
        var username = Environment.GetEnvironmentVariable("LOGIN_NAME") ?? "paolo";
        if (string.IsNullOrWhiteSpace(username))
        {
            throw new InvalidOperationException("LOGIN_NAME is set to an empty value");
        }

        var server = Environment.GetEnvironmentVariable("SQL_SERVER");
        var database = Environment.GetEnvironmentVariable("SQL_DATABASE");
        var user = Environment.GetEnvironmentVariable("SQL_USERNAME");
        var password = Environment.GetEnvironmentVariable("SQL_PASSWORD");
        var useAzureCredential = Environment.GetEnvironmentVariable("AZURE_CLIENT_ID") is { Length: > 0 }
            && Environment.GetEnvironmentVariable("AZURE_CLIENT_SECRET") is { Length: > 0 }
            && Environment.GetEnvironmentVariable("AZURE_TENANT_ID") is { Length: > 0 };

        if (string.IsNullOrEmpty(server) || string.IsNullOrEmpty(database) || (!useAzureCredential && (string.IsNullOrEmpty(user) || string.IsNullOrEmpty(password))))
        {
            throw new InvalidOperationException(
                "Set SQL_SERVER and SQL_DATABASE, with SQL_USERNAME and SQL_PASSWORD or the AZURE_CLIENT_ID, AZURE_CLIENT_SECRET and AZURE_TENANT_ID service principal variables.");
        }

        return new SqlOptions(server, database, user, password, useAzureCredential, username);
    }
}
