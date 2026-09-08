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
var storageOptions = FileStorageOptions.FromEnvironment();

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
builder.Services.AddSingleton(storageOptions);
builder.Services.AddSingleton<IActivityStore>(sp =>
    new FileActivityStore(storageOptions, sp.GetRequiredService<ILogger<FileActivityStore>>()));
builder.Services.AddHostedService(sp =>
    new StoreInitializer(sp.GetRequiredService<IActivityStore>(), sp.GetRequiredService<ILogger<StoreInitializer>>()));

var app = builder.Build();

if (string.IsNullOrEmpty(secretKey))
{
    app.Logger.LogWarning("SECRET_KEY is not set: antiforgery tokens and flash messages are only valid on this replica.");
}

app.UseStaticFiles();
app.MapRazorPages();

app.MapGet("/health", async (IActivityStore store, CancellationToken cancellationToken) =>
    await store.IsHealthyAsync(cancellationToken)
        ? Results.Json(new { status = "ok" })
        : Results.Json(new { status = "unavailable" }, statusCode: StatusCodes.Status503ServiceUnavailable));

app.Run();
