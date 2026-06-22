/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ['./src/**/*.{js,jsx,ts,tsx}'],
  theme: {
    extend: {
      colors: {
        fincorp: {
          navy: '#0f2044',
          blue: '#1a3a6b',
          gold: '#c9a84c',
          light: '#f0f4f8',
        },
      },
    },
  },
  plugins: [],
};
