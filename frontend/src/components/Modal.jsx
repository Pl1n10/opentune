import { useEffect } from 'react'
import { X } from 'lucide-react'
import { clsx } from 'clsx'

export function Modal({ isOpen, onClose, title, children, size = 'md' }) {
  // Close on Escape key
  useEffect(() => {
    function handleEscape(e) {
      if (e.key === 'Escape') onClose()
    }
    
    if (isOpen) {
      document.addEventListener('keydown', handleEscape)
      document.body.style.overflow = 'hidden'
    }
    
    return () => {
      document.removeEventListener('keydown', handleEscape)
      document.body.style.overflow = ''
    }
  }, [isOpen, onClose])

  if (!isOpen) return null

  const sizes = {
    sm: 'max-w-md',
    md: 'max-w-lg',
    lg: 'max-w-2xl',
    xl: 'max-w-4xl',
  }

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto">
      {/* Backdrop */}
      <div 
        className="fixed inset-0 bg-gray-900/50 transition-opacity"
        onClick={onClose}
      />
      
      {/* Modal container */}
      <div className="flex min-h-full items-center justify-center p-4">
        <div className={clsx(
          'relative w-full bg-white rounded-xl shadow-xl transform transition-all',
          sizes[size]
        )}>
          {/* Header */}
          <div className="flex items-center justify-between px-6 py-4 border-b border-gray-100">
            <h2 className="text-lg font-semibold text-gray-900">{title}</h2>
            <button
              onClick={onClose}
              className="p-1 rounded-md text-gray-400 hover:text-gray-500 hover:bg-gray-100 transition-colors"
            >
              <X className="w-5 h-5" />
            </button>
          </div>
          
          {/* Content */}
          <div className="px-6 py-4">
            {children}
          </div>
        </div>
      </div>
    </div>
  )
}

export function ModalFooter({ children }) {
  return (
    <div className="flex items-center justify-end gap-3 mt-6 pt-4 border-t border-gray-100">
      {children}
    </div>
  )
}
