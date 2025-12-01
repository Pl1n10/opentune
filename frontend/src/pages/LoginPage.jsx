import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Key, AlertCircle, Loader2 } from 'lucide-react'
import { useAuth } from '../context/AuthContext'
import { Button, Input, Card, CardContent } from '../components/ui'

export default function LoginPage() {
  const [apiKey, setApiKey] = useState('')
  const [error, setError] = useState('')
  const [isLoading, setIsLoading] = useState(false)
  const { login } = useAuth()
  const navigate = useNavigate()

  const handleSubmit = async (e) => {
    e.preventDefault()
    setError('')
    setIsLoading(true)

    if (!apiKey.trim()) {
      setError('Please enter your API key')
      setIsLoading(false)
      return
    }

    try {
      // Test the API key
      const response = await fetch('/api/v1/nodes?limit=1', {
        headers: {
          'X-Admin-API-Key': apiKey,
        },
      })

      if (response.ok) {
        login(apiKey)
        navigate('/')
      } else if (response.status === 401) {
        setError('Invalid API key. Please check and try again.')
      } else {
        setError(`Connection failed: ${response.status}`)
      }
    } catch (err) {
      setError('Cannot connect to the server. Is the backend running?')
    } finally {
      setIsLoading(false)
    }
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-50 to-gray-100 flex items-center justify-center p-4">
      <div className="w-full max-w-md">
        {/* Logo */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-16 h-16 bg-gradient-to-br from-primary-500 to-primary-700 rounded-2xl mb-4 shadow-lg">
            <svg className="w-9 h-9 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
            </svg>
          </div>
          <h1 className="text-2xl font-bold text-gray-900">OpenTune</h1>
          <p className="text-gray-500 mt-1">GitOps Control Plane for Windows DSC</p>
        </div>

        {/* Login Card */}
        <Card>
          <CardContent className="p-6">
            <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Admin API Key
                </label>
                <div className="relative">
                  <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                    <Key className="h-5 w-5 text-gray-400" />
                  </div>
                  <input
                    type="password"
                    value={apiKey}
                    onChange={(e) => setApiKey(e.target.value)}
                    placeholder="Enter your API key"
                    className="block w-full pl-10 pr-3 py-2.5 border border-gray-300 rounded-lg text-sm placeholder:text-gray-400 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-primary-500"
                    autoFocus
                  />
                </div>
              </div>

              {error && (
                <div className="flex items-center gap-2 p-3 bg-red-50 border border-red-200 rounded-lg text-sm text-red-700">
                  <AlertCircle className="w-4 h-4 flex-shrink-0" />
                  {error}
                </div>
              )}

              <Button 
                type="submit" 
                className="w-full" 
                size="lg"
                disabled={isLoading}
              >
                {isLoading ? (
                  <>
                    <Loader2 className="w-4 h-4 animate-spin" />
                    Connecting...
                  </>
                ) : (
                  'Connect'
                )}
              </Button>
            </form>

            <div className="mt-6 pt-6 border-t border-gray-100">
              <p className="text-xs text-gray-500 text-center">
                The API key is stored locally in your browser and sent with each request.
              </p>
            </div>
          </CardContent>
        </Card>

        {/* Help text */}
        <p className="text-center text-sm text-gray-500 mt-6">
          Find your API key in the backend's <code className="px-1 py-0.5 bg-gray-100 rounded">.env</code> file
        </p>
      </div>
    </div>
  )
}
