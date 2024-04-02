import express from 'express';

const app = express();
const MAX_AGE = 1000 * 60;

app.use(express.static('public', { maxAge: MAX_AGE }));

app.get('/', (req, res) => {
  res.send('hello');
});

app.listen(3000);
