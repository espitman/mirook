/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        paper: "#fffdf8",
        cream: "#f4efe6",
        ink: "#171717",
        muted: "#6f6a60",
        line: "#e5dfd5"
      },
      fontFamily: {
        vazir: ["Vazirmatn", "Tahoma", "Arial", "sans-serif"],
        ui: ["Inter", "-apple-system", "BlinkMacSystemFont", "Segoe UI", "sans-serif"],
        serif: ["Georgia", "Times New Roman", "serif"]
      },
      boxShadow: {
        soft: "0 18px 55px rgba(20, 18, 14, 0.12)"
      }
    }
  },
  plugins: []
};
