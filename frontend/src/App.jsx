import React, { useState } from 'react';

const API_URL = process.env.REACT_APP_API_URL || '';

function formatCurrency(value) {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(value);
}

function InputField({ label, id, value, onChange, min, max, step, prefix, suffix }) {
  return (
    <div className="flex flex-col gap-1">
      <label htmlFor={id} className="text-sm font-medium text-gray-600 uppercase tracking-wide">
        {label}
      </label>
      <div className="relative flex items-center">
        {prefix && (
          <span className="absolute left-3 text-gray-400 font-medium select-none">{prefix}</span>
        )}
        <input
          id={id}
          type="number"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          min={min}
          max={max}
          step={step}
          className={`w-full border border-gray-200 rounded-lg py-3 pr-3 bg-white text-gray-800 font-medium focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition ${prefix ? 'pl-8' : 'pl-3'}`}
        />
        {suffix && (
          <span className="absolute right-3 text-gray-400 font-medium select-none">{suffix}</span>
        )}
      </div>
    </div>
  );
}

function StatCard({ label, value, highlight }) {
  return (
    <div className={`rounded-xl p-5 flex flex-col gap-1 ${highlight ? 'bg-fincorp-navy text-white' : 'bg-white border border-gray-100'}`}>
      <span className={`text-xs font-semibold uppercase tracking-widest ${highlight ? 'text-blue-200' : 'text-gray-400'}`}>
        {label}
      </span>
      <span className={`text-2xl font-bold ${highlight ? 'text-white' : 'text-fincorp-navy'}`}>
        {value}
      </span>
    </div>
  );
}

export default function App() {
  const [principal, setPrincipal] = useState(250000);
  const [annualRate, setAnnualRate] = useState(6.5);
  const [termYears, setTermYears] = useState(30);
  const [result, setResult] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [showSchedule, setShowSchedule] = useState(false);

  const handleCalculate = async () => {
    setError('');
    setLoading(true);
    try {
      const res = await fetch(`${API_URL}/api/calculate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          principal: parseFloat(principal),
          annualRate: parseFloat(annualRate),
          termMonths: parseInt(termYears) * 12,
        }),
      });
      if (!res.ok) {
        const data = await res.json();
        throw new Error(data.error || 'Calculation failed');
      }
      const data = await res.json();
      setResult(data);
      setShowSchedule(false);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-fincorp-light">
      {/* Header */}
      <header className="bg-fincorp-navy shadow-lg">
        <div className="max-w-5xl mx-auto px-6 py-4 flex items-center gap-3">
          <div className="w-9 h-9 rounded-lg bg-fincorp-gold flex items-center justify-center font-bold text-fincorp-navy text-lg">
            F
          </div>
          <div>
            <h1 className="text-white font-bold text-xl leading-tight">FinCorp</h1>
            <p className="text-blue-300 text-xs">Loan Calculator</p>
          </div>
        </div>
      </header>

      <main className="max-w-5xl mx-auto px-6 py-10 flex flex-col gap-8">
        {/* Hero */}
        <div>
          <h2 className="text-3xl font-bold text-fincorp-navy">Loan Calculator</h2>
          <p className="text-gray-500 mt-1">Estimate your monthly payments and total cost of borrowing.</p>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Input panel */}
          <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-6 flex flex-col gap-5">
            <h3 className="font-semibold text-fincorp-navy text-lg border-b border-gray-100 pb-3">
              Loan Details
            </h3>

            <InputField
              label="Loan Amount"
              id="principal"
              value={principal}
              onChange={setPrincipal}
              min={1000}
              max={10000000}
              step={1000}
              prefix="$"
            />
            <InputField
              label="Annual Interest Rate"
              id="annualRate"
              value={annualRate}
              onChange={setAnnualRate}
              min={0}
              max={30}
              step={0.1}
              suffix="%"
            />
            <InputField
              label="Loan Term"
              id="termYears"
              value={termYears}
              onChange={setTermYears}
              min={1}
              max={30}
              step={1}
              suffix="yrs"
            />

            {error && (
              <div className="bg-red-50 border border-red-200 rounded-lg px-4 py-3 text-red-600 text-sm">
                {error}
              </div>
            )}

            <button
              onClick={handleCalculate}
              disabled={loading}
              className="mt-2 w-full bg-fincorp-navy hover:bg-fincorp-blue text-white font-semibold py-3 rounded-xl transition disabled:opacity-50"
            >
              {loading ? 'Calculating...' : 'Calculate'}
            </button>
          </div>

          {/* Results panel */}
          <div className="flex flex-col gap-4">
            {result ? (
              <>
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                  <StatCard
                    label="Monthly Payment"
                    value={formatCurrency(result.summary.monthlyPayment)}
                    highlight
                  />
                  <StatCard
                    label="Total Payment"
                    value={formatCurrency(result.summary.totalPayment)}
                  />
                  <StatCard
                    label="Total Interest"
                    value={formatCurrency(result.summary.totalInterest)}
                  />
                </div>

                {/* Interest vs Principal bar */}
                <div className="bg-white rounded-2xl border border-gray-100 p-5 shadow-sm">
                  <p className="text-xs font-semibold uppercase tracking-widest text-gray-400 mb-3">
                    Payment Breakdown
                  </p>
                  <div className="flex rounded-full overflow-hidden h-5">
                    <div
                      className="bg-fincorp-navy transition-all"
                      style={{
                        width: `${(principal / result.summary.totalPayment) * 100}%`,
                      }}
                    />
                    <div className="bg-fincorp-gold flex-1" />
                  </div>
                  <div className="flex justify-between mt-2 text-xs text-gray-500">
                    <span className="flex items-center gap-1">
                      <span className="w-2.5 h-2.5 rounded-full bg-fincorp-navy inline-block" />
                      Principal ({((principal / result.summary.totalPayment) * 100).toFixed(1)}%)
                    </span>
                    <span className="flex items-center gap-1">
                      <span className="w-2.5 h-2.5 rounded-full bg-fincorp-gold inline-block" />
                      Interest ({((result.summary.totalInterest / result.summary.totalPayment) * 100).toFixed(1)}%)
                    </span>
                  </div>
                </div>

                <button
                  onClick={() => setShowSchedule(!showSchedule)}
                  className="text-fincorp-navy font-medium text-sm underline underline-offset-2 text-left"
                >
                  {showSchedule ? 'Hide' : 'Show'} amortization schedule
                </button>
              </>
            ) : (
              <div className="bg-white rounded-2xl border border-gray-100 p-10 shadow-sm flex flex-col items-center justify-center text-center text-gray-400 h-full min-h-[200px]">
                <svg className="w-12 h-12 mb-3 text-gray-200" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9 7h6m0 10v-3m-3 3h.01M9 17h.01M9 11h.01M12 11h.01M15 11h.01M4 6h16M4 10h16M4 14h16M4 18h16" />
                </svg>
                <p className="font-medium">Enter loan details and calculate</p>
                <p className="text-sm mt-1">Your results will appear here</p>
              </div>
            )}
          </div>
        </div>

        {/* Amortization table */}
        {showSchedule && result && (
          <div className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden">
            <div className="px-6 py-4 border-b border-gray-100">
              <h3 className="font-semibold text-fincorp-navy">Amortization Schedule</h3>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="bg-fincorp-light text-gray-500 uppercase text-xs tracking-wider">
                    <th className="text-left px-6 py-3">Month</th>
                    <th className="text-right px-6 py-3">Payment</th>
                    <th className="text-right px-6 py-3">Principal</th>
                    <th className="text-right px-6 py-3">Interest</th>
                    <th className="text-right px-6 py-3">Balance</th>
                  </tr>
                </thead>
                <tbody>
                  {result.schedule.map((row) => (
                    <tr key={row.month} className="border-t border-gray-50 hover:bg-gray-50">
                      <td className="px-6 py-2.5 text-gray-500">{row.month}</td>
                      <td className="px-6 py-2.5 text-right font-medium text-fincorp-navy">{formatCurrency(row.payment)}</td>
                      <td className="px-6 py-2.5 text-right text-green-600">{formatCurrency(row.principal)}</td>
                      <td className="px-6 py-2.5 text-right text-amber-600">{formatCurrency(row.interest)}</td>
                      <td className="px-6 py-2.5 text-right text-gray-600">{formatCurrency(row.balance)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </main>

      <footer className="text-center text-xs text-gray-400 py-8">
        © 2024 FinCorp Financial Services · Secure · Auditable · Always Available
      </footer>
    </div>
  );
}
