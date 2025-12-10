import { BrowserRouter as Router, Routes, Route, Link } from 'react-router-dom'
import HomePage from './pages/HomePage'
import PrivacyPage from './pages/PrivacyPage'
import RequestAccountRestorePage from './pages/RequestAccountRestorePage'

function App() {
  return (
    <Router>
      <nav className="p-4 bg-gray-800 text-white">
        <Link to="/" className="mr-4">Home</Link>
        <Link to="/privacy">Privacy</Link>
      </nav>
      <Routes>
        <Route path="/" element={<HomePage />} />
        <Route path="/privacy" element={<PrivacyPage />} />
        <Route path="/request-account-restore" element={<RequestAccountRestorePage />} />
      </Routes>
    </Router>
  )
}

export default App

