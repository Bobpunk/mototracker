const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const sqlite3 = require('sqlite3').verbose();
const path = require('path');

// Configurar fuso horário do Brasil
process.env.TZ = 'America/Sao_Paulo';

// Função para converter UTC para horário do Brasil
function toBrazilTime(utcString) {
  const date = new Date(utcString);
  // Converter para fuso horário do Brasil (UTC-3)
  const brazilTime = new Date(date.getTime() - (3 * 60 * 60 * 1000));
  
  return brazilTime.toLocaleString('pt-BR', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit'
  });
}

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(bodyParser.json());
app.use(express.static('public'));

// Configuração do banco de dados
const dbPath = process.env.DATABASE_URL || './motoboy_tracker.db';
const db = new sqlite3.Database(dbPath);

// Criar tabelas se não existirem
db.serialize(() => {
  // Tabela de motoboys
  db.run(`CREATE TABLE IF NOT EXISTS motoboys (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    phone TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT 1
  )`);

  // Tabela de sessões
  db.run(`CREATE TABLE IF NOT EXISTS sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    motoboy_id TEXT NOT NULL,
    odometer REAL NOT NULL,
    start_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    end_time DATETIME,
    is_active BOOLEAN DEFAULT 1,
    total_distance REAL DEFAULT 0,
    end_odometer REAL,
    FOREIGN KEY (motoboy_id) REFERENCES motoboys (id)
  )`);

  // Tabela de localizações
  db.run(`CREATE TABLE IF NOT EXISTS locations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    motoboy_id TEXT NOT NULL,
    session_id INTEGER,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    accuracy REAL DEFAULT 0,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (motoboy_id) REFERENCES motoboys (id),
    FOREIGN KEY (session_id) REFERENCES sessions (id)
  )`);
});

// API Routes

// 1. Registrar motoboy
app.post('/api/motoboys', (req, res) => {
  const { id, name, phone } = req.body;
  
  if (!id || !name) {
    return res.status(400).json({ error: 'ID e nome são obrigatórios' });
  }

  const sql = `INSERT OR REPLACE INTO motoboys (id, name, phone) VALUES (?, ?, ?)`;
  
  db.run(sql, [id, name, phone || ''], function(err) {
    if (err) {
      console.error('Erro ao registrar motoboy:', err);
      return res.status(500).json({ error: 'Erro interno do servidor' });
    }
    
    res.json({ 
      success: true, 
      message: 'Motoboy registrado com sucesso',
      data: { id, name, phone: phone || '' }
    });
  });
});

// 2. Listar sessões ativas
app.get('/api/sessions', (req, res) => {
  const sql = `
    SELECT s.*, m.name as motoboy_name 
    FROM sessions s 
    JOIN motoboys m ON s.motoboy_id = m.id 
    WHERE s.is_active = 1 
    ORDER BY s.start_time DESC
  `;
  
  db.all(sql, [], (err, rows) => {
    if (err) {
      console.error('Erro ao buscar sessões:', err);
      return res.status(500).json({ error: 'Erro interno do servidor' });
    }
    
    // Converter horários para fuso do Brasil
    const rowsWithBrazilTime = rows.map(row => ({
      ...row,
      start_time: toBrazilTime(row.start_time),
      end_time: row.end_time ? toBrazilTime(row.end_time) : null
    }));
    
    res.json({ success: true, data: rowsWithBrazilTime });
  });
});

// 3. Iniciar sessão de trabalho
app.post('/api/sessions', (req, res) => {
  const { motoboyId, motoboy_id, odometer } = req.body;
  const motoboyIdFinal = motoboyId || motoboy_id;
  
  if (!motoboyIdFinal || !odometer) {
    return res.status(400).json({ error: 'ID do motoboy e odômetro são obrigatórios' });
  }

  // Primeiro, finalizar todas as sessões ativas do mesmo motoboy
  const finalizeSql = `UPDATE sessions 
                       SET end_time = CURRENT_TIMESTAMP, 
                           is_active = 0 
                       WHERE motoboy_id = ? AND is_active = 1`;
  
  db.run(finalizeSql, [motoboyIdFinal], function(err) {
    if (err) {
      console.error('Erro ao finalizar sessões anteriores:', err);
      return res.status(500).json({ error: 'Erro interno do servidor' });
    }
    
    // Agora criar nova sessão
    const sql = `INSERT INTO sessions (motoboy_id, odometer) VALUES (?, ?)`;
    
    db.run(sql, [motoboyIdFinal, parseFloat(odometer)], function(err) {
      if (err) {
        console.error('Erro ao iniciar sessão:', err);
        return res.status(500).json({ error: 'Erro interno do servidor' });
      }
      
      res.json({ 
        success: true, 
        message: 'Sessão iniciada com sucesso',
        sessionId: this.lastID,
        data: { motoboyId: motoboyIdFinal, odometer: parseFloat(odometer) }
      });
    });
  });
});

// 3. Finalizar sessão
app.put('/api/sessions/:sessionId/end', (req, res) => {
  const { sessionId } = req.params;
  const { odometer } = req.body;

  const sql = `UPDATE sessions 
               SET end_time = CURRENT_TIMESTAMP, 
                   is_active = 0, 
                   end_odometer = ?, 
                   total_distance = ? - odometer 
               WHERE id = ?`;

  // Primeiro, obter o odômetro inicial
  db.get(`SELECT odometer FROM sessions WHERE id = ?`, [sessionId], (err, row) => {
    if (err) {
      console.error('Erro ao obter sessão:', err);
      return res.status(500).json({ error: 'Erro interno do servidor' });
    }

    if (!row) {
      return res.status(404).json({ error: 'Sessão não encontrada' });
    }

    const totalDistance = parseFloat(odometer) - row.odometer;

    db.run(sql, [parseFloat(odometer), parseFloat(odometer), sessionId], function(err) {
      if (err) {
        console.error('Erro ao finalizar sessão:', err);
        return res.status(500).json({ error: 'Erro interno do servidor' });
      }

      res.json({ 
        success: true, 
        message: 'Sessão finalizada com sucesso',
        totalDistance: totalDistance
      });
    });
  });
});

// 4. Enviar localização
app.post('/api/locations', (req, res) => {
  const { motoboyId, motoboy_id, sessionId, latitude, longitude, accuracy, timestamp } = req.body;
  const motoboyIdFinal = motoboyId || motoboy_id;
  
  if (!motoboyIdFinal || !latitude || !longitude) {
    return res.status(400).json({ error: 'Dados de localização incompletos' });
  }

  const sql = `INSERT INTO locations (motoboy_id, session_id, latitude, longitude, accuracy, timestamp) 
               VALUES (?, ?, ?, ?, ?, ?)`;
  
  const timestampValue = timestamp ? new Date(timestamp).toISOString() : new Date().toISOString();
  
  db.run(sql, [motoboyIdFinal, sessionId, parseFloat(latitude), parseFloat(longitude), 
               parseFloat(accuracy) || 0, timestampValue], function(err) {
    if (err) {
      console.error('Erro ao enviar localização:', err);
      return res.status(500).json({ error: 'Erro interno do servidor' });
    }
    
    res.json({ 
      success: true, 
      message: 'Localização enviada com sucesso',
      locationId: this.lastID
    });
  });
});

// 5. Listar motoboys
app.get('/api/motoboys', (req, res) => {
  const sql = `SELECT * FROM motoboys ORDER BY created_at DESC`;
  
  db.all(sql, [], (err, rows) => {
    if (err) {
      console.error('Erro ao listar motoboys:', err);
      return res.status(500).json({ error: 'Erro interno do servidor' });
    }
    
    res.json({ success: true, data: rows });
  });
});

// 6. Listar todas as localizações recentes
app.get('/api/locations', (req, res) => {
  const sql = `
    SELECT l.*, m.name as motoboy_name 
    FROM locations l 
    JOIN motoboys m ON l.motoboy_id = m.id 
    ORDER BY l.timestamp DESC 
    LIMIT 100
  `;
  
  db.all(sql, [], (err, rows) => {
    if (err) {
      console.error('Erro ao buscar localizações:', err);
      return res.status(500).json({ error: 'Erro interno do servidor' });
    }
    
    res.json({ success: true, data: rows });
  });
});

// 7. Obter localizações de um motoboy
app.get('/api/locations/:motoboyId', (req, res) => {
  const { motoboyId } = req.params;
  const { limit = 100 } = req.query;

  const sql = `SELECT * FROM locations 
               WHERE motoboy_id = ? 
               ORDER BY timestamp DESC 
               LIMIT ?`;
  
  db.all(sql, [motoboyId, parseInt(limit)], (err, rows) => {
    if (err) {
      console.error('Erro ao obter localizações:', err);
      return res.status(500).json({ error: 'Erro interno do servidor' });
    }
    
    res.json({ success: true, data: rows });
  });
});

// 7. Relatório geral
app.get('/api/report', (req, res) => {
  const { startDate, endDate } = req.query;
  
  let sql = `SELECT 
    s.motoboy_id,
    m.name,
    COUNT(s.id) as total_sessions,
    COALESCE(SUM(s.total_distance), 0) as total_distance,
    COALESCE(AVG(s.total_distance), 0) as average_distance,
    MIN(s.start_time) as first_session,
    MAX(s.start_time) as last_session
  FROM sessions s
  LEFT JOIN motoboys m ON s.motoboy_id = m.id
  WHERE 1=1`;

  const params = [];

  if (startDate && endDate) {
    sql += ` AND s.start_time BETWEEN ? AND ?`;
    params.push(startDate, endDate);
  }

  sql += ` GROUP BY s.motoboy_id, m.name ORDER BY total_sessions DESC`;

  db.all(sql, params, (err, rows) => {
    if (err) {
      console.error('Erro ao gerar relatório:', err);
      return res.status(500).json({ error: 'Erro interno do servidor' });
    }
    
    res.json({ 
      success: true, 
      data: rows,
      totalSessions: rows.reduce((sum, row) => sum + row.total_sessions, 0)
    });
  });
});

// 8. Dashboard web
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// 9. Health check
app.get('/health', (req, res) => {
  res.json({ 
    status: 'OK', 
    timestamp: new Date().toISOString(),
    database: 'Connected',
    platform: 'Railway'
  });
});

// Iniciar servidor
app.listen(PORT, () => {
  console.log(`🚀 Servidor rodando na porta ${PORT}`);
  console.log(`📱 Dashboard: http://localhost:${PORT}`);
  console.log(`🔗 API: http://localhost:${PORT}/api`);
  console.log(`💚 Health: http://localhost:${PORT}/health`);
  console.log('');
  console.log('📋 Para deploy no Railway:');
  console.log('1. Crie conta: https://railway.app');
  console.log('2. Conecte GitHub');
  console.log('3. Deploy automático');
});

module.exports = app;
