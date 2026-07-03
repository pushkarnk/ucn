using Humanizer;
using Serilog;

var builder = WebApplication.CreateBuilder(args);

// Configure Serilog (NuGet: Serilog.AspNetCore) as the logging provider.
builder.Host.UseSerilog((context, configuration) =>
    configuration.WriteTo.Console());

// Bind only to the loopback interface on port 5000.
builder.WebHost.UseUrls("http://127.0.0.1:5000");

var app = builder.Build();

app.UseSerilogRequestLogging();

app.MapGet("/", () => "Hello, World! This is a sample dotnet app listening on 127.0.0.1:5000");

// Demonstrate the Humanizer NuGet package.
app.MapGet("/humanize/{count:int}", (int count) => new
{
    count,
    word = "item".ToQuantity(count),
    ordinal = count.Ordinalize(),
    spelledOut = count.ToWords()
});

app.MapGet("/health", () => Results.Ok(new { status = "healthy" }));

app.Run();
