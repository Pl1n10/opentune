import { useState, useEffect, useCallback } from 'react'

/**
 * Generic hook for API data fetching with loading/error states
 */
export function useApi(fetchFn, deps = []) {
  const [data, setData] = useState(null)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState(null)

  const refetch = useCallback(async () => {
    setIsLoading(true)
    setError(null)
    try {
      const result = await fetchFn()
      setData(result)
    } catch (err) {
      setError(err.message || 'An error occurred')
      console.error('API Error:', err)
    } finally {
      setIsLoading(false)
    }
  }, [fetchFn])

  useEffect(() => {
    refetch()
  }, deps)

  return { data, isLoading, error, refetch, setData }
}

/**
 * Hook for mutations (POST, PUT, DELETE)
 */
export function useMutation(mutationFn) {
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState(null)

  const mutate = useCallback(async (...args) => {
    setIsLoading(true)
    setError(null)
    try {
      const result = await mutationFn(...args)
      return result
    } catch (err) {
      setError(err.message || 'An error occurred')
      throw err
    } finally {
      setIsLoading(false)
    }
  }, [mutationFn])

  return { mutate, isLoading, error }
}

/**
 * Debounce hook
 */
export function useDebounce(value, delay = 300) {
  const [debouncedValue, setDebouncedValue] = useState(value)

  useEffect(() => {
    const handler = setTimeout(() => {
      setDebouncedValue(value)
    }, delay)

    return () => clearTimeout(handler)
  }, [value, delay])

  return debouncedValue
}
