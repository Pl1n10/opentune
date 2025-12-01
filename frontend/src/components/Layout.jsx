import { NavLink, useNavigate } from 'react-router-dom'
import { 
  LayoutDashboard, 
  Server, 
  FileCode, 
  GitBranch, 
  Settings,
  LogOut,
  Menu,
  X
} from 'lucide-react'
import { useState } from 'react'
import { useAuth } from '../context/AuthContext'

const navigation = [
  { name: 'Dashboard', href: '/', icon: LayoutDashboard },
  { name: 'Nodes', href: '/nodes', icon: Server },
  { name: 'Policies', href: '/policies', icon: FileCode },
  { name: 'Repositories', href: '/repositories', icon: GitBranch },
]

function Sidebar({ isOpen, onClose }) {
  const { logout } = useAuth()
  const navigate = useNavigate()

  const handleLogout = () => {
    logout()
    navigate('/login')
  }

  return (
    <>
      {/* Mobile overlay */}
      {isOpen && (
        <div 
          className="fixed inset-0 bg-gray-900/50 z-40 lg:hidden"
          onClick={onClose}
        />
      )}

      {/* Sidebar */}
      <aside className={`
        fixed top-0 left-0 z-50 h-full w-64 bg-white border-r border-gray-200
        transform transition-transform duration-200 ease-in-out
        lg:translate-x-0 lg:static lg:z-auto
        ${isOpen ? 'translate-x-0' : '-translate-x-full'}
      `}>
        {/* Logo */}
        <div className="h-16 flex items-center justify-between px-6 border-b border-gray-200">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 bg-gradient-to-br from-primary-500 to-primary-700 rounded-lg flex items-center justify-center">
              <svg className="w-5 h-5 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
              </svg>
            </div>
            <span className="font-semibold text-gray-900">OpenTune</span>
          </div>
          <button 
            onClick={onClose}
            className="lg:hidden p-1 rounded-md hover:bg-gray-100"
          >
            <X className="w-5 h-5 text-gray-500" />
          </button>
        </div>

        {/* Navigation */}
        <nav className="flex-1 px-3 py-4 space-y-1">
          {navigation.map((item) => (
            <NavLink
              key={item.name}
              to={item.href}
              onClick={onClose}
              className={({ isActive }) => `
                flex items-center gap-3 px-3 py-2 rounded-lg text-sm font-medium
                transition-colors
                ${isActive 
                  ? 'bg-primary-50 text-primary-700' 
                  : 'text-gray-700 hover:bg-gray-100'
                }
              `}
            >
              <item.icon className="w-5 h-5" />
              {item.name}
            </NavLink>
          ))}
        </nav>

        {/* Footer */}
        <div className="p-3 border-t border-gray-200">
          <button
            onClick={handleLogout}
            className="flex items-center gap-3 w-full px-3 py-2 rounded-lg text-sm font-medium text-gray-700 hover:bg-gray-100 transition-colors"
          >
            <LogOut className="w-5 h-5" />
            Disconnect
          </button>
        </div>
      </aside>
    </>
  )
}

export default function Layout({ children }) {
  const [sidebarOpen, setSidebarOpen] = useState(false)

  return (
    <div className="min-h-screen bg-gray-50 flex">
      <Sidebar isOpen={sidebarOpen} onClose={() => setSidebarOpen(false)} />
      
      <div className="flex-1 flex flex-col min-w-0">
        {/* Top bar for mobile */}
        <header className="lg:hidden h-16 bg-white border-b border-gray-200 flex items-center px-4">
          <button
            onClick={() => setSidebarOpen(true)}
            className="p-2 rounded-md hover:bg-gray-100"
          >
            <Menu className="w-5 h-5 text-gray-600" />
          </button>
          <div className="flex items-center gap-2 ml-3">
            <div className="w-7 h-7 bg-gradient-to-br from-primary-500 to-primary-700 rounded-lg flex items-center justify-center">
              <svg className="w-4 h-4 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
              </svg>
            </div>
            <span className="font-semibold text-gray-900">OpenTune</span>
          </div>
        </header>

        {/* Main content */}
        <main className="flex-1 p-6 overflow-auto">
          {children}
        </main>
      </div>
    </div>
  )
}
