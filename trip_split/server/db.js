// server/db.js
const sql = require('mssql/msnodesqlv8');
require('dotenv').config();

const connectionString = process.env.DB_CONNECTION_STRING || 
  `Driver={ODBC Driver 17 for SQL Server};Server=${process.env.DB_SERVER || 'localhost'};Database=${process.env.DB_NAME || 'SPLIT_BILL_DB'};Trusted_Connection=Yes;`;

const config = {
  connectionString: connectionString,
};

let pool = null;

async function getPool() {
  if (pool) return pool;

  try {
    console.log(`[DB] Connecting to SQL Server with connection string: ${connectionString}`);
    pool = await sql.connect(config);
    console.log(`[DB] Connected to SQL Server database "${process.env.DB_NAME || 'SPLIT_BILL_DB'}" successfully!`);
    return pool;
  } catch (err) {
    console.error('[DB] Database connection error:', err);
    throw err;
  }
}

module.exports = {
  sql,
  getPool,
};
