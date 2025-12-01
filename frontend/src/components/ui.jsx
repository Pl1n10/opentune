import { clsx } from 'clsx'
import { Loader2 } from 'lucide-react'

// =============================================================================
// Card
// =============================================================================

export function Card({ children, className, ...props }) {
  return (
    <div 
      className={clsx(
        'bg-white rounded-xl border border-gray-200 shadow-sm',
        className
      )}
      {...props}
    >
      {children}
    </div>
  )
}

export function CardHeader({ children, className }) {
  return (
    <div className={clsx('px-6 py-4 border-b border-gray-100', className)}>
      {children}
    </div>
  )
}

export function CardTitle({ children, className }) {
  return (
    <h3 className={clsx('text-lg font-semibold text-gray-900', className)}>
      {children}
    </h3>
  )
}

export function CardContent({ children, className }) {
  return (
    <div className={clsx('px-6 py-4', className)}>
      {children}
    </div>
  )
}

// =============================================================================
// Button
// =============================================================================

const buttonVariants = {
  primary: 'bg-primary-600 text-white hover:bg-primary-700 focus:ring-primary-500',
  secondary: 'bg-white text-gray-700 border border-gray-300 hover:bg-gray-50 focus:ring-primary-500',
  danger: 'bg-red-600 text-white hover:bg-red-700 focus:ring-red-500',
  ghost: 'text-gray-700 hover:bg-gray-100 focus:ring-gray-500',
}

const buttonSizes = {
  sm: 'px-3 py-1.5 text-sm',
  md: 'px-4 py-2 text-sm',
  lg: 'px-5 py-2.5 text-base',
}

export function Button({ 
  children, 
  variant = 'primary', 
  size = 'md',
  isLoading = false,
  disabled = false,
  className,
  ...props 
}) {
  return (
    <button
      disabled={disabled || isLoading}
      className={clsx(
        'inline-flex items-center justify-center gap-2 font-medium rounded-lg',
        'focus:outline-none focus:ring-2 focus:ring-offset-2',
        'disabled:opacity-50 disabled:cursor-not-allowed',
        'transition-colors',
        buttonVariants[variant],
        buttonSizes[size],
        className
      )}
      {...props}
    >
      {isLoading && <Loader2 className="w-4 h-4 animate-spin" />}
      {children}
    </button>
  )
}

// =============================================================================
// Status Badge
// =============================================================================

const statusStyles = {
  success: 'bg-green-100 text-green-800',
  failed: 'bg-red-100 text-red-800',
  error: 'bg-red-100 text-red-800',
  unknown: 'bg-gray-100 text-gray-800',
  registered: 'bg-blue-100 text-blue-800',
  in_progress: 'bg-yellow-100 text-yellow-800',
  skipped: 'bg-gray-100 text-gray-600',
}

const statusDots = {
  success: 'bg-green-500',
  failed: 'bg-red-500',
  error: 'bg-red-500',
  unknown: 'bg-gray-400',
  registered: 'bg-blue-500',
  in_progress: 'bg-yellow-500',
  skipped: 'bg-gray-400',
}

export function StatusBadge({ status, showDot = true, className }) {
  const normalizedStatus = status?.toLowerCase() || 'unknown'
  
  return (
    <span className={clsx(
      'inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-medium',
      statusStyles[normalizedStatus] || statusStyles.unknown,
      className
    )}>
      {showDot && (
        <span className={clsx(
          'w-1.5 h-1.5 rounded-full',
          statusDots[normalizedStatus] || statusDots.unknown
        )} />
      )}
      {status || 'Unknown'}
    </span>
  )
}

// =============================================================================
// Input
// =============================================================================

export function Input({ label, error, className, ...props }) {
  return (
    <div className="space-y-1">
      {label && (
        <label className="block text-sm font-medium text-gray-700">
          {label}
        </label>
      )}
      <input
        className={clsx(
          'block w-full rounded-lg border border-gray-300 px-3 py-2 text-sm',
          'placeholder:text-gray-400',
          'focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-primary-500',
          error && 'border-red-500 focus:ring-red-500 focus:border-red-500',
          className
        )}
        {...props}
      />
      {error && (
        <p className="text-sm text-red-600">{error}</p>
      )}
    </div>
  )
}

// =============================================================================
// Select
// =============================================================================

export function Select({ label, error, children, className, ...props }) {
  return (
    <div className="space-y-1">
      {label && (
        <label className="block text-sm font-medium text-gray-700">
          {label}
        </label>
      )}
      <select
        className={clsx(
          'block w-full rounded-lg border border-gray-300 px-3 py-2 text-sm',
          'focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-primary-500',
          'bg-white',
          error && 'border-red-500 focus:ring-red-500 focus:border-red-500',
          className
        )}
        {...props}
      >
        {children}
      </select>
      {error && (
        <p className="text-sm text-red-600">{error}</p>
      )}
    </div>
  )
}

// =============================================================================
// Loading Spinner
// =============================================================================

export function LoadingSpinner({ size = 'md', className }) {
  const sizes = {
    sm: 'w-4 h-4',
    md: 'w-8 h-8',
    lg: 'w-12 h-12',
  }
  
  return (
    <Loader2 className={clsx('animate-spin text-primary-600', sizes[size], className)} />
  )
}

// =============================================================================
// Empty State
// =============================================================================

export function EmptyState({ icon: Icon, title, description, action }) {
  return (
    <div className="text-center py-12">
      {Icon && (
        <div className="mx-auto w-12 h-12 rounded-full bg-gray-100 flex items-center justify-center mb-4">
          <Icon className="w-6 h-6 text-gray-400" />
        </div>
      )}
      <h3 className="text-sm font-medium text-gray-900">{title}</h3>
      {description && (
        <p className="mt-1 text-sm text-gray-500">{description}</p>
      )}
      {action && (
        <div className="mt-4">{action}</div>
      )}
    </div>
  )
}

// =============================================================================
// Page Header
// =============================================================================

export function PageHeader({ title, description, action }) {
  return (
    <div className="mb-6 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">{title}</h1>
        {description && (
          <p className="mt-1 text-sm text-gray-500">{description}</p>
        )}
      </div>
      {action && <div>{action}</div>}
    </div>
  )
}

// =============================================================================
// Stat Card
// =============================================================================

export function StatCard({ title, value, icon: Icon, trend, trendUp, className }) {
  return (
    <Card className={clsx('', className)}>
      <CardContent className="flex items-center gap-4">
        {Icon && (
          <div className="p-3 rounded-lg bg-primary-50">
            <Icon className="w-6 h-6 text-primary-600" />
          </div>
        )}
        <div className="flex-1 min-w-0">
          <p className="text-sm font-medium text-gray-500 truncate">{title}</p>
          <p className="text-2xl font-bold text-gray-900">{value}</p>
          {trend && (
            <p className={clsx(
              'text-sm font-medium',
              trendUp ? 'text-green-600' : 'text-red-600'
            )}>
              {trend}
            </p>
          )}
        </div>
      </CardContent>
    </Card>
  )
}
