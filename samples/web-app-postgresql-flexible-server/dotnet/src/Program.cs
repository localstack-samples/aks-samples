using System.Diagnostics;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.DataProtection.KeyManagement;
using VacationPlanner.Services;

var builder = WebApplication.CreateBuilder(args);

// Listen on PORT (8080 by default), the way the Python image binds gunicorn to 0.0.0.0:${PORT}. HTTP_PORTS is the
// same setting the aspnet base image feeds through ASPNETCORE_HTTP_PORTS, so no URL override is involved.
if (Environment.GetEnvironmentVariable("PORT") is { Length: > 0 } port)
{
    builder.WebHost.UseSetting(WebHostDefaults.HttpPortsKey, port);
}

// Read and validate the configuration up front so a misconfigured deployment fails at startup.
var storeOptions = PostgresOptions.FromEnvironment();

// SECRET_KEY is the Kubernetes Secret the Python sample signs its session cookie with. Deriving the Data Protection
// key ring from it lets all replicas validate each other's antiforgery tokens and flash cookies; without it (a local
// docker run) each process keeps its own keys.
var secretKey = Environment.GetEnvironmentVariable("SECRET_KEY");
if (!string.IsNullOrEmpty(secretKey))
{
    builder.Services.AddDataProtection().DisableAutomaticKeyGeneration();
    builder.Services.Configure<KeyManagementOptions>(options => options.XmlRepository = new SecretKeyXmlRepository(secretKey));
}

builder.Services.AddRazorPages();
builder.Services.AddSingleton<IActivityStore>(sp =>
    new PostgresActivityStore(storeOptions, sp.GetRequiredService<ILogger<PostgresActivityStore>>()));
// The Python sample waits up to 30 x 2 s for the database at startup; the same values apply here.
builder.Services.AddHostedService(sp =>
    new StoreInitializer(sp.GetRequiredService<IActivityStore>(), sp.GetRequiredService<ILogger<StoreInitializer>>(),
        attempts: 30, delay: TimeSpan.FromSeconds(2)));

var app = builder.Build();

if (string.IsNullOrEmpty(secretKey))
{
    app.Logger.LogWarning("SECRET_KEY is not set: antiforgery tokens and flash messages are only valid on this replica.");
}

// One log line per request, the equivalent of the access log the Python image produces (its gunicorn
// command passes --access-logfile -). Kubernetes probes show up here too, exactly as they do for Python.
var requestLogger = app.Services.GetRequiredService<ILoggerFactory>().CreateLogger("VacationPlanner.Requests");
app.Use(
    async (context, next) =>
    {
        var started = Stopwatch.GetTimestamp();
        await next();
        requestLogger.LogInformation(
            "{Method} {Path} -> {StatusCode} in {Elapsed:0.0}ms",
            context.Request.Method,
            context.Request.Path,
            context.Response.StatusCode,
            Stopwatch.GetElapsedTime(started).TotalMilliseconds
        );
    }
);

app.UseStaticFiles();
app.MapRazorPages();

app.MapGet("/health", async (IActivityStore store, CancellationToken cancellationToken) =>
    await store.IsHealthyAsync(cancellationToken)
        ? Results.Json(new { status = "ok" })
        : Results.Json(new { status = "unavailable" }, statusCode: StatusCodes.Status503ServiceUnavailable));

app.Run();
