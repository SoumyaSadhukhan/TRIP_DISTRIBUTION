using System.Data;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

namespace TripDistribution.Services.Data
{
    public interface ISqlDbConnectionFactory
    {
        IDbConnection CreateConnection();
    }

    public class SqlDbConnectionFactory : ISqlDbConnectionFactory
    {
        private readonly string _connectionString;

        public SqlDbConnectionFactory(IConfiguration configuration)
        {
            _connectionString = configuration.GetConnectionString("DefaultConnection") 
                ?? "Data Source=localhost;Initial Catalog=SPLIT_BILL_DB;Integrated Security=True;Encrypt=False;TrustServerCertificate=True;";
        }

        public IDbConnection CreateConnection()
        {
            return new SqlConnection(_connectionString);
        }
    }
}
