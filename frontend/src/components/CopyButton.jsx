import { useState } from 'react'
import { Copy, Check, AlertCircle } from 'lucide-react'
import { copyToClipboard } from '../utils/url'

/**
 * A button component that copies text to clipboard with visual feedback.
 * 
 * Shows different states:
 * - Default: Copy icon
 * - Success: Check icon + "Copied!" text (2 seconds)
 * - Error: Alert icon + "Failed" text (2 seconds)
 */
export function CopyButton({ 
  text, 
  className = '',
  variant = 'secondary',
  size = 'sm',
  label = null,  // Optional label to show next to icon
}) {
  const [status, setStatus] = useState('idle') // 'idle' | 'copied' | 'error'

  const handleCopy = async (e) => {
    e.preventDefault()
    e.stopPropagation()
    
    const success = await copyToClipboard(text)
    
    if (success) {
      setStatus('copied')
    } else {
      setStatus('error')
    }
    
    // Reset after 2 seconds
    setTimeout(() => setStatus('idle'), 2000)
  }

  // Base button styles matching the existing Button component
  const baseStyles = 'inline-flex items-center justify-center gap-1.5 font-medium rounded-lg transition-colors focus:outline-none focus:ring-2 focus:ring-offset-2'
  
  const variantStyles = {
    secondary: 'bg-white border border-gray-300 text-gray-700 hover:bg-gray-50 focus:ring-gray-500',
    ghost: 'text-gray-500 hover:text-gray-700 hover:bg-gray-100 focus:ring-gray-500',
  }
  
  const sizeStyles = {
    sm: 'px-2.5 py-1.5 text-xs',
    md: 'px-3 py-2 text-sm',
  }

  // Status-specific styles
  const statusStyles = {
    idle: '',
    copied: 'bg-green-50 border-green-300 text-green-700',
    error: 'bg-red-50 border-red-300 text-red-700',
  }

  const Icon = status === 'copied' ? Check : status === 'error' ? AlertCircle : Copy
  const statusLabel = status === 'copied' ? 'Copied!' : status === 'error' ? 'Failed' : label

  return (
    <button
      type="button"
      onClick={handleCopy}
      className={`
        ${baseStyles}
        ${variantStyles[variant]}
        ${sizeStyles[size]}
        ${status !== 'idle' ? statusStyles[status] : ''}
        ${className}
      `}
      title={status === 'idle' ? 'Copy to clipboard' : undefined}
    >
      <Icon className="w-4 h-4" />
      {statusLabel && <span>{statusLabel}</span>}
    </button>
  )
}

/**
 * A code block with an integrated copy button.
 * Perfect for showing commands or tokens that users need to copy.
 */
export function CodeBlockWithCopy({ 
  code, 
  language = 'powershell',
  label = 'Copy',
  className = '',
}) {
  return (
    <div className={`relative group ${className}`}>
      <pre className="p-4 bg-gray-900 text-gray-100 rounded-lg overflow-x-auto text-sm font-mono whitespace-pre-wrap break-all">
        <code>{code}</code>
      </pre>
      <div className="absolute top-2 right-2">
        <CopyButton 
          text={code} 
          variant="secondary"
          size="sm"
          label={label}
          className="opacity-80 hover:opacity-100 bg-gray-700 border-gray-600 text-gray-200 hover:bg-gray-600"
        />
      </div>
    </div>
  )
}
