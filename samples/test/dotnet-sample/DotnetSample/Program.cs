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
    word = Greeting.ToQuantity(count),
    ordinal = Greeting.Ordinalize(count),
    spelledOut = Greeting.ToWords(count)
});

app.MapGet("/health", () => Results.Ok(new { status = "healthy" }));

app.Run();

// Expose entry assembly for WebApplicationFactory in the test project.
public partial class Program { }

public static class Greeting
{
    public static string ToQuantity(int count) => "item".ToQuantity(count);

    // Humanizer.Ordinalize()/ToWords() build locale-specific formatters (e.g. CultureInfo("en-US"))
    // in a static initializer, which throws under DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=true.
    // Chiseled runtime images don't ship ICU, so implement these two without Humanizer.
    public static string Ordinalize(int count) => (count % 100) switch
    {
        11 or 12 or 13 => $"{count}th",
        _ => (count % 10) switch
        {
            1 => $"{count}st",
            2 => $"{count}nd",
            3 => $"{count}rd",
            _ => $"{count}th"
        }
    };

    private static readonly string[] Ones =
        ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"];

    public static string ToWords(int count) =>
        count is >= 0 and < 10 ? Ones[count] : count.ToString();
}
