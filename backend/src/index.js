const express = require('express');
const cors = require('cors');
const helmet = require('helmet');

const app = express();
const PORT = process.env.PORT || 3001;

app.use(helmet());
app.use(cors());
app.use(express.json());

// Calculate monthly mortgage/loan payment using the standard amortization formula
function calculateLoan({ principal, annualRate, termMonths }) {
  if (annualRate === 0) {
    return {
      monthlyPayment: principal / termMonths,
      totalPayment: principal,
      totalInterest: 0,
    };
  }

  const monthlyRate = annualRate / 100 / 12;
  const monthlyPayment =
    (principal * (monthlyRate * Math.pow(1 + monthlyRate, termMonths))) /
    (Math.pow(1 + monthlyRate, termMonths) - 1);

  const totalPayment = monthlyPayment * termMonths;
  const totalInterest = totalPayment - principal;

  return {
    monthlyPayment: parseFloat(monthlyPayment.toFixed(2)),
    totalPayment: parseFloat(totalPayment.toFixed(2)),
    totalInterest: parseFloat(totalInterest.toFixed(2)),
  };
}

// Build full amortization schedule
function buildSchedule({ principal, annualRate, termMonths }) {
  const monthlyRate = annualRate / 100 / 12;
  const { monthlyPayment } = calculateLoan({ principal, annualRate, termMonths });
  let balance = principal;
  const schedule = [];

  for (let month = 1; month <= termMonths; month++) {
    const interestPayment = parseFloat((balance * monthlyRate).toFixed(2));
    const principalPayment = parseFloat((monthlyPayment - interestPayment).toFixed(2));
    balance = parseFloat((balance - principalPayment).toFixed(2));

    schedule.push({
      month,
      payment: monthlyPayment,
      principal: principalPayment,
      interest: interestPayment,
      balance: Math.max(0, balance),
    });
  }

  return schedule;
}

app.post('/api/calculate', (req, res) => {
  const { principal, annualRate, termMonths } = req.body;

  if (!principal || annualRate === undefined || !termMonths) {
    return res.status(400).json({ error: 'principal, annualRate, and termMonths are required' });
  }
  if (principal <= 0 || termMonths <= 0 || annualRate < 0) {
    return res.status(400).json({ error: 'Invalid input values' });
  }

  const summary = calculateLoan({ principal, annualRate, termMonths });
  const schedule = buildSchedule({ principal, annualRate, termMonths });

  res.json({ summary, schedule });
});

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'fincorp-loan-api', version: '1.0.0' });
});

app.listen(PORT, () => {
  console.log(`FinCorp Loan API running on port ${PORT}`);
});
