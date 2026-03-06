// project_folder/trivia-server/questions.js

// Embedded question bank for demo.
// All question types match Flutter QuestionType enum values exactly:
//   mcq, true_false, type_in, image_based

const QUESTIONS = [
  {
    id: 'q1',
    type: 'mcq',
    text: 'What is the capital of France?',
    options: ['London', 'Berlin', 'Paris', 'Madrid'],
    correct: 'Paris',
    timer_seconds: 15,
  },
  {
    id: 'q2',
    type: 'mcq',
    text: 'Which planet is closest to the Sun?',
    options: ['Venus', 'Mercury', 'Earth', 'Mars'],
    correct: 'Mercury',
    timer_seconds: 15,
  },
  {
    id: 'q3',
    type: 'true_false',
    text: 'The Great Wall of China is visible from space.',
    options: ['True', 'False'],
    correct: 'false',
    timer_seconds: 10,
  },
  {
    id: 'q4',
    type: 'mcq',
    text: 'What is the largest ocean on Earth?',
    options: ['Atlantic', 'Indian', 'Arctic', 'Pacific'],
    correct: 'Pacific',
    timer_seconds: 15,
  },
  {
    id: 'q5',
    type: 'true_false',
    text: 'A group of flamingos is called a flamboyance.',
    options: ['True', 'False'],
    correct: 'true',
    timer_seconds: 10,
  },
  {
    id: 'q6',
    type: 'mcq',
    text: 'How many sides does a hexagon have?',
    options: ['5', '6', '7', '8'],
    correct: '6',
    timer_seconds: 10,
  },
  {
    id: 'q7',
    type: 'type_in',
    text: 'What is the chemical symbol for water?',
    options: [],
    correct: 'h2o',          // compared case-insensitively on server
    timer_seconds: 20,
  },
  {
    id: 'q8',
    type: 'mcq',
    text: 'Who painted the Mona Lisa?',
    options: ['Van Gogh', 'Picasso', 'Da Vinci', 'Rembrandt'],
    correct: 'Da Vinci',
    timer_seconds: 15,
  },
  {
    id: 'q9',
    type: 'true_false',
    text: 'Sharks are mammals.',
    options: ['True', 'False'],
    correct: 'false',
    timer_seconds: 10,
  },
  {
    id: 'q10',
    type: 'mcq',
    text: 'What year did the first iPhone launch?',
    options: ['2005', '2006', '2007', '2008'],
    correct: '2007',
    timer_seconds: 15,
  },
];

module.exports = { QUESTIONS };