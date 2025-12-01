/**
 * API Client for OpenTune backend
 */

const API_BASE = '/api/v1'

class ApiError extends Error {
  constructor(message, status, data) {
    super(message)
    this.status = status
    this.data = data
  }
}

async function request(endpoint, options = {}) {
  const apiKey = localStorage.getItem('opentune_api_key')

  const config = {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      'X-Admin-API-Key': apiKey || '',
      ...options.headers,
    },
  }

  const response = await fetch(`${API_BASE}${endpoint}`, config)

  if (!response.ok) {
    let errorData = null
    try {
      errorData = await response.json()
    } catch {
      // Response might not be JSON
    }
    throw new ApiError(
      errorData?.detail || `Request failed with status ${response.status}`,
      response.status,
      errorData
    )
  }

  // Handle 204 No Content
  if (response.status === 204) {
    return null
  }

  return response.json()
}

// Helper: normalizza qualsiasi "lista" in un array
const normalizeList = (data) => {
  if (Array.isArray(data)) return data
  if (Array.isArray(data?.items)) return data.items
  return []
}

// =============================================================================
// Nodes API
// =============================================================================

export const nodesApi = {
  list: (params = {}) => {
    const query = new URLSearchParams(params).toString()
    return request(`/nodes${query ? `?${query}` : ''}`).then(normalizeList)
  },

  get: (id) => request(`/nodes/${id}`),

  create: (data) => request('/nodes', {
    method: 'POST',
    body: JSON.stringify(data),
  }),

  delete: (id) => request(`/nodes/${id}`, {
    method: 'DELETE',
  }),

  assignPolicy: (nodeId, policyId) => request(`/nodes/${nodeId}/policy`, {
    method: 'PUT',
    body: JSON.stringify({ policy_id: policyId }),
  }),

  getRuns: (nodeId, params = {}) => {
    const query = new URLSearchParams(params).toString()
    return request(`/nodes/${nodeId}/runs${query ? `?${query}` : ''}`).then(normalizeList)
  },

  regenerateToken: (id) => request(`/nodes/${id}/regenerate-token`, {
    method: 'POST',
  }),
}

// =============================================================================
// Repositories API
// =============================================================================

export const repositoriesApi = {
  list: (params = {}) => {
    const query = new URLSearchParams(params).toString()
    return request(`/repositories${query ? `?${query}` : ''}`).then(normalizeList)
  },

  get: (id) => request(`/repositories/${id}`),

  create: (data) => request('/repositories', {
    method: 'POST',
    body: JSON.stringify(data),
  }),

  update: (id, data) => request(`/repositories/${id}`, {
    method: 'PUT',
    body: JSON.stringify(data),
  }),

  delete: (id, force = false) => request(`/repositories/${id}?force=${force}`, {
    method: 'DELETE',
  }),
}

// =============================================================================
// Policies API
// =============================================================================

export const policiesApi = {
  list: (params = {}) => {
    const query = new URLSearchParams(params).toString()
    return request(`/policies${query ? `?${query}` : ''}`).then(normalizeList)
  },

  get: (id) => request(`/policies/${id}`),

  create: (data) => request('/policies', {
    method: 'POST',
    body: JSON.stringify(data),
  }),

  update: (id, data) => request(`/policies/${id}`, {
    method: 'PUT',
    body: JSON.stringify(data),
  }),

  delete: (id, force = false) => request(`/policies/${id}?force=${force}`, {
    method: 'DELETE',
  }),

  getNodes: (id) => request(`/policies/${id}/nodes`).then(normalizeList),
}

// =============================================================================
// Runs API
// =============================================================================

export const runsApi = {
  list: (params = {}) => {
    const query = new URLSearchParams(params).toString()
    return request(`/runs${query ? `?${query}` : ''}`).then(normalizeList)
  },

  get: (id) => request(`/runs/${id}`),

  getStats: (hours = 24) => request(`/runs/stats?hours=${hours}`),
}

// =============================================================================
// Health API
// =============================================================================

export const healthApi = {
  check: () => fetch('/health').then(r => r.json()),
}

export { ApiError }
