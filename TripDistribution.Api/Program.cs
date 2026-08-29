using System.Net;
using System.Net.Sockets;
using TripDistribution.Api.Middleware;
using TripDistribution.Services.Data;
using TripDistribution.Services.Services;

var builder = WebApplication.CreateBuilder(args);

// Dynamic Free Port Finder - never fails with address already in use!
builder.WebHost.ConfigureKestrel(serverOptions =>
{
    int[] preferredPorts = new[] { 5246, 7266, 5055, 5100, 8080, 8090 };
    int selectedPort = 0;
    
    foreach (var port in preferredPorts)
    {
        try {
            var listener = new TcpListener(IPAddress.Any, port);
            listener.Start();
            listener.Stop();
            selectedPort = port;
            break;
        } catch { }
    }

    if (selectedPort == 0)
    {
        var listener = new TcpListener(IPAddress.Any, 0);
        listener.Start();
        selectedPort = ((IPEndPoint)listener.LocalEndpoint).Port;
        listener.Stop();
    }

    serverOptions.Listen(IPAddress.Any, selectedPort);
});

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

// Register Core Services & Logger
builder.Services.AddSingleton<IFileLoggerService, FileLoggerService>();
builder.Services.AddSingleton<ISqlDbConnectionFactory, SqlDbConnectionFactory>();
builder.Services.AddScoped<IUserService, UserService>();
builder.Services.AddScoped<ITripService, TripService>();
builder.Services.AddScoped<IExpenseService, ExpenseService>();
builder.Services.AddScoped<IFriendService, FriendService>();
builder.Services.AddScoped<ISettlementService, SettlementService>();

var app = builder.Build();

// Enable File Logger Middleware for all API calls
app.UseMiddleware<RequestLoggingMiddleware>();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(c =>
    {
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "Trip Distribution API v1");
        c.RoutePrefix = "swagger";
    });
}

// Redirect root / to /swagger
app.MapGet("/", () => Results.Redirect("/swagger"));

app.UseCors("AllowAll");
app.UseAuthorization();
app.MapControllers();

app.Lifetime.ApplicationStarted.Register(() =>
{
    var logger = app.Services.GetRequiredService<IFileLoggerService>();
    logger.LogInfo("Trip Distribution Web API Server started successfully.", "STARTUP");

    Console.ForegroundColor = ConsoleColor.Green;
    Console.WriteLine("\n==================================================================");
    Console.WriteLine("  TRIP DISTRIBUTION API STARTED SUCCESSFULLY!");
    Console.WriteLine("  Logger Active => C:\\My_Project\\TRIP_DISTRIBUTION\\logggg\\");
    Console.WriteLine("  Connect your Mobile Phone / Web App to:");
    foreach (var address in app.Urls)
    {
        Console.WriteLine($"   -> {address}/swagger");
    }
    Console.WriteLine("==================================================================\n");
    Console.ResetColor();
});

app.Run();
