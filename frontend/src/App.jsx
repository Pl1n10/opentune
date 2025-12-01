import { Routes, Route, Navigate } from 'react-router-dom'
import { useAuth } from './context/AuthContext'
import Layout from './components/Layout'
import LoginPage from './pages/LoginPage'
import DashboardPage from './pages/DashboardPage'
import NodesPage from './pages/NodesPage'
import NodeDetailPage from './pages/NodeDetailPage'
import PoliciesPage from './pages/PoliciesPage'
import RepositoriesPage from './pages/RepositoriesPage'
import { LoadingSpinner } from './components/ui'

// Protected route wrapper
function ProtectedRoute({ children }) {
  const { isAuthenticated, isLoading } = useAuth()

  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <LoadingSpinner size="lg" />
      </div>
    )
  }

  if (!isAuthenticated) {
    return <Navigate to="/login" replace />
  }

  return <Layout>{children}</Layout>
}

// Public route wrapper (redirect to dashboard if already authenticated)
function PublicRoute({ children }) {
  const { isAuthenticated, isLoading } = useAuth()

  if (isLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <LoadingSpinner size="lg" />
      </div>
    )
  }

  if (isAuthenticated) {
    return <Navigate to="/" replace />
  }

  return children
}

export default function App() {
  return (
    <Routes>
      {/* Public routes */}
      <Route 
        path="/login" 
        element={
          <PublicRoute>
            <LoginPage />
          </PublicRoute>
        } 
      />

      {/* Protected routes */}
      <Route
        path="/"
        element={
          <ProtectedRoute>
            <DashboardPage />
          </ProtectedRoute>
        }
      />
      
      <Route
        path="/nodes"
        element={
          <ProtectedRoute>
            <NodesPage />
          </ProtectedRoute>
        }
      />
      
      <Route
        path="/nodes/:id"
        element={
          <ProtectedRoute>
            <NodeDetailPage />
          </ProtectedRoute>
        }
      />
      
      <Route
        path="/policies"
        element={
          <ProtectedRoute>
            <PoliciesPage />
          </ProtectedRoute>
        }
      />
      
      <Route
        path="/repositories"
        element={
          <ProtectedRoute>
            <RepositoriesPage />
          </ProtectedRoute>
        }
      />

      {/* Catch all - redirect to dashboard */}
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}
