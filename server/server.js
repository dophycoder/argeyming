const express = require('express');
const http = require('http');
const { Server } = require('socket.io');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

// --- STATE ---
const players = {};
const HIT_RADIUS = 50;

// --- NETWORK LOGIC ---
io.on('connection', (socket) => {
  console.log(`Player connected: ${socket.id}`);

  socket.on('join', (data) => {
    players[socket.id] = {
      x: data.x,
      y: data.y,
      hp: 100
    };
    io.emit('stateUpdate', players);
  });

  socket.on('move', (data) => {
    if (players[socket.id]) {
      players[socket.id].x = data.x;
      players[socket.id].y = data.y;
      io.emit('stateUpdate', players);
    }
  });

  socket.on('shoot', (data) => {
    if (!players[socket.id]) return;
    const shooter = players[socket.id];
    
    for (const [id, target] of Object.entries(players)) {
      if (id !== socket.id) {
        const dx = target.x - shooter.x;
        const dy = target.y - shooter.y;
        const distance = Math.sqrt(dx * dx + dy * dy);
        
        if (distance < HIT_RADIUS) {
          target.hp -= 10;
          if (target.hp < 0) target.hp = 0;
          
          io.to(id).emit('hit', { targetId: id, shooterId: socket.id });
          io.emit('stateUpdate', players);
        }
      }
    }
  });

  socket.on('disconnect', () => {
    console.log(`Player disconnected: ${socket.id}`);
    delete players[socket.id];
    io.emit('stateUpdate', players);
  });
});

server.listen(3000, () => {
  console.log('Listening on *:3000');
});