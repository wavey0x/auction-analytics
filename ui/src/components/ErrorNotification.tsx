import React from 'react'
import { X, AlertTriangle, AlertCircle, Info } from 'lucide-react'
import { useErrors, type AppError, type ErrorSeverity } from '../context/ErrorContext'
import ChainIcon from './ChainIcon'

const getSeverityIcon = (severity: ErrorSeverity) => {
  switch (severity) {
    case 'error':
      return <X className="h-4 w-4" />
    case 'warning':
      return <AlertTriangle className="h-4 w-4" />
    case 'info':
      return <Info className="h-4 w-4" />
    default:
      return <AlertCircle className="h-4 w-4" />
  }
}

const getSeverityStyles = (severity: ErrorSeverity) => {
  switch (severity) {
    case 'error':
      return {
        bg: 'bg-red-600/95',
        border: 'border-red-500',
        text: 'text-white',
        button: 'hover:bg-red-700'
      }
    case 'warning':
      return {
        bg: 'bg-yellow-600/95',
        border: 'border-yellow-500',
        text: 'text-white',
        button: 'hover:bg-yellow-700'
      }
    case 'info':
      return {
        bg: 'bg-blue-600/95',
        border: 'border-blue-500',
        text: 'text-white',
        button: 'hover:bg-blue-700'
      }
    default:
      return {
        bg: 'bg-gray-600/95',
        border: 'border-gray-500',
        text: 'text-white',
        button: 'hover:bg-gray-700'
      }
  }
}

const ErrorNotificationItem: React.FC<{
  error: AppError
  onDismiss: (id: string) => void
}> = ({ error, onDismiss }) => {
  const styles = getSeverityStyles(error.severity)
  const icon = getSeverityIcon(error.severity)

  return (
    <div className={`${styles.bg} ${styles.border} ${styles.text} border backdrop-blur-xl`}>
      <div className="px-6 py-3">
        <div className="flex items-center justify-between gap-4">
          <div className="flex items-center gap-3 min-w-0 flex-1">
            {/* Severity icon */}
            <div className="flex-shrink-0">
              {icon}
            </div>
            
            {/* Chain icon (if applicable) */}
            {error.chainId && (
              <div className="flex-shrink-0">
                <ChainIcon chainId={error.chainId} size="sm" showName={false} />
              </div>
            )}
            
            {/* Error content */}
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <span className="font-semibold text-sm">{error.title}</span>
                {error.source && (
                  <span className="text-xs opacity-75 bg-black/20 px-2 py-1 rounded">
                    {error.source}
                  </span>
                )}
              </div>
              <p className="text-xs opacity-90 mt-1 truncate">{error.message}</p>
              {error.details && (
                <p className="text-xs opacity-75 mt-1 font-mono truncate">{error.details}</p>
              )}
            </div>
            
            {/* Timestamp */}
            <div className="flex-shrink-0 text-xs opacity-75">
              {new Date(error.timestamp).toLocaleTimeString()}
            </div>
          </div>
          
          {/* Dismiss button */}
          <button
            onClick={() => onDismiss(error.id)}
            className={`flex-shrink-0 p-1 rounded transition-colors ${styles.button}`}
            aria-label="Dismiss error"
          >
            <X className="h-3 w-3" />
          </button>
        </div>
      </div>
    </div>
  )
}

const ErrorNotification: React.FC = () => {
  const { errors, removeError, clearAllErrors } = useErrors()

  if (errors.length === 0) {
    return null
  }

  return (
    <div className="fixed bottom-16 left-0 right-0 z-50 animate-in slide-in-from-bottom-2 duration-300">
      <div className="space-y-0">
        {errors.map((error) => (
          <ErrorNotificationItem
            key={error.id}
            error={error}
            onDismiss={removeError}
          />
        ))}
        
        {/* Clear all button (when multiple errors) */}
        {errors.length > 1 && (
          <div className="bg-gray-800/95 border-t border-gray-700 backdrop-blur-xl">
            <div className="px-6 py-2 text-center">
              <button
                onClick={clearAllErrors}
                className="text-xs text-gray-300 hover:text-white transition-colors underline"
              >
                Clear all {errors.length} errors
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

export default ErrorNotification