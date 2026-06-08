const express = require('express');
const http = require('http');
const { Server } = require('socket.io');

const app = express();
const server = http.createServer(app);
const io = new Server(server, { cors: { origin: "*", methods: ["GET", "POST"] } });

// --- STATE ---
const rooms = {}; 

// --- NETWORK LOGIC ---
io.on('connection', (socket) => {
  console.log(`Connected: ${socket.id}`);

  socket.on('createRoom', () => {
    const roomId = Math.random().toString(36).substring(2, 8).toUpperCase();
    rooms[roomId] = {
      players: { [socket.id]: { ready: false, hp: 100 } },
      state: 'lobby'
    };
    socket.join(roomId);
    socket.emit('roomCreated', { roomId });
  });

  socket.on('joinRoom', (data) => {
    const roomId = data.roomId;
    if (rooms[roomId] && Object.keys(rooms[roomId].players).length < 2) {
      rooms[roomId].players[socket.id] = { ready: false, hp: 100 };
      socket.join(roomId);
      io.to(roomId).emit('playerJoined', { players: rooms[roomId].players });
    } else {
      socket.emit('error', { message: 'Room not found or full' });
    }
  });

  socket.on('setReady', (data) => {
    const roomId = data.roomId;
    if (rooms[roomId] && rooms[roomId].players[socket.id]) {
      rooms[roomId].players[socket.id].ready = true;
      const pKeys = Object.keys(rooms[roomId].players);
      if (pKeys.length === 2 && rooms[roomId].players[pKeys[0]].ready && rooms[roomId].players[pKeys[1]].ready) {
        rooms[roomId].state = 'playing';
        io.to(roomId).emit('gameStart', { players: rooms[roomId].players });
      } else {
        io.to(roomId).emit('playerReady', { playerId: socket.id });
      }
    }
  });

  socket.on('move', (data) => {
    const roomId = data.roomId;
    if (rooms[roomId] && rooms[roomId].players[socket.id]) {
      socket.to(roomId).emit('enemyMove', { id: socket.id, yaw: data.yaw, pitch: data.pitch });
    }
  });

  socket.on('shoot', (data) => {
    const roomId = data.roomId;
    if (rooms[roomId] && rooms[roomId].state === 'playing') {
      const pKeys = Object.keys(rooms[roomId].players);
      const enemyId = pKeys.find(id => id !== socket.id);
      
      if (enemyId && data.hit) {
        rooms[roomId].players[enemyId].hp -= 20;
        if (rooms[roomId].players[enemyId].hp <= 0) {
          rooms[roomId].players[enemyId].hp = 0;
          io.to(roomId).emit('gameOver', { winner: socket.id });
          delete rooms[roomId];
        } else {
          io.to(roomId).emit('hit', { targetId: enemyId, hp: rooms[roomId].players[enemyId].hp });
        }
      }
    }
  });

  socket.on('disconnect', () => {
    for (const roomId in rooms) {
      if (rooms[roomId].players[socket.id]) {
        socket.to(roomId).emit('error', { message: 'Opponent disconnected' });
        delete rooms[roomId];
      }
    }
  });
});

// --- NETWORK ERROR HANDLING ---
io.engine.on("connection_error", (err) => {
  console.log(err.req, err.code, err.message, err.context);
});

server.listen(3000, () => {
  console.log('Listening on *:3000');
});