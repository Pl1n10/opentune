/**
 * URL utilities for OpenTune frontend
 * 
 * Handles server URL resolution for bootstrap scripts and API calls.
 * Supports both environment variable configuration and automatic detection.
 */

/**
 * Get the server base URL for API/bootstrap calls.
 * 
 * Priority:
 * 1. VITE_SERVER_URL environment variable (for explicit configuration)
 * 2. window.location.origin (auto-detect from current page)
 * 
 * @returns {string} Base URL like "http://192.168.178.63:8000"
 */
export function getServerBaseUrl() {
  // Check for explicit environment variable first
  // This allows overriding in .env or .env.local:
  // VITE_SERVER_URL=http://192.168.178.63:8000
  if (import.meta.env.VITE_SERVER_URL) {
    // Remove trailing slash if present
    return import.meta.env.VITE_SERVER_URL.replace(/\/$/, '')
  }
  
  // Fall back to current page origin (works for most setups)
  return window.location.origin
}

/**
 * Build the full bootstrap script URL for a node.
 * 
 * @param {number} nodeId - The node ID
 * @param {string} token - The node authentication token
 * @returns {string} Full URL like "http://server:8000/api/v1/agents/nodes/1/bootstrap.ps1?token=xxx"
 */
export function getBootstrapUrl(nodeId, token) {
  const baseUrl = getServerBaseUrl()
  return `${baseUrl}/api/v1/agents/nodes/${nodeId}/bootstrap.ps1?token=${encodeURIComponent(token)}`
}

/**
 * Generate a complete PowerShell bootstrap command that can be copy-pasted
 * and run on a Windows machine.
 * 
 * @param {number} nodeId - The node ID
 * @param {string} nodeName - The node name (for filename)
 * @param {string} token - The node authentication token
 * @returns {string} Complete PowerShell script
 */
export function generatePowerShellBootstrapCommand(nodeId, nodeName, token) {
  const bootstrapUrl = getBootstrapUrl(nodeId, token)
  // Sanitize node name for use in filename (remove invalid chars)
  const safeNodeName = nodeName.replace(/[^a-zA-Z0-9_-]/g, '-')
  
  return `# OpenTune Bootstrap Script for node: ${nodeName}
# Run this in PowerShell as Administrator

Set-ExecutionPolicy Bypass -Scope Process -Force

Invoke-WebRequest \`
  "${bootstrapUrl}" \`
  -OutFile "C:\\dsc-agent\\bootstrap-${safeNodeName}.ps1"

# Execute the bootstrap script
& "C:\\dsc-agent\\bootstrap-${safeNodeName}.ps1"`
}

/**
 * Copy text to clipboard with fallback for older browsers.
 * 
 * @param {string} text - Text to copy
 * @returns {Promise<boolean>} True if successful, false otherwise
 */
export async function copyToClipboard(text) {
  // Modern browsers with Clipboard API
  if (navigator.clipboard && navigator.clipboard.writeText) {
    try {
      await navigator.clipboard.writeText(text)
      return true
    } catch (err) {
      console.warn('Clipboard API failed, trying fallback:', err)
    }
  }
  
  // Fallback for older browsers or when Clipboard API is blocked
  try {
    const textArea = document.createElement('textarea')
    textArea.value = text
    textArea.style.position = 'fixed'
    textArea.style.left = '-9999px'
    textArea.style.top = '-9999px'
    document.body.appendChild(textArea)
    textArea.focus()
    textArea.select()
    
    const success = document.execCommand('copy')
    document.body.removeChild(textArea)
    return success
  } catch (err) {
    console.error('Fallback copy failed:', err)
    return false
  }
}
