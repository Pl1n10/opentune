import { createContext, useContext, useState, useEffect } from 'react'

const AuthContext = createContext(null)

const STORAGE_KEY = 'opentune_api_key'

export function AuthProvider({ children }) {
  const [apiKey, setApiKey] = useState(() => {
    return localStorage.getItem(STORAGE_KEY) || ''
  })
  const [isAuthenticated, setIsAuthenticated] = useState(false)
  const [isLoading, setIsLoading] = useState(true)

  // Verify API key on mount and when it changes
  useEffect(() => {
    async function verifyKey() {
      if (!apiKey) {
        setIsAuthenticated(false)
        setIsLoading(false)
        return
      }

      try {
        const response = await fetch('/api/v1/nodes?limit=1', {
          headers: {
            'X-Admin-API-Key': apiKey,
          },
        })
        
        if (response.ok) {
          setIsAuthenticated(true)
          localStorage.setItem(STORAGE_KEY, apiKey)
        } else {
          setIsAuthenticated(false)
          localStorage.removeItem(STORAGE_KEY)
        }
      } catch (error) {
        console.error('Auth verification failed:', error)
        setIsAuthenticated(false)
      } finally {
        setIsLoading(false)
      }
    }

    verifyKey()
  }, [apiKey])

  const login = (key) => {
    setIsLoading(true)
    setApiKey(key)
  }

  const logout = () => {
    setApiKey('')
    setIsAuthenticated(false)
    localStorage.removeItem(STORAGE_KEY)
  }

  return (
    <AuthContext.Provider value={{ 
      apiKey, 
      isAuthenticated, 
      isLoading, 
      login, 
      logout 
    }}>
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider')
  }
  return context
}
