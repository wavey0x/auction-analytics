import React, { createContext, useContext, useState, useCallback } from 'react'

// Error types
export type ErrorSeverity = 'error' | 'warning' | 'info'

export interface AppError {
  id: string
  title: string
  message: string
  severity: ErrorSeverity
  timestamp: number
  source?: string // e.g., 'RPC', 'API', 'Indexer'
  chainId?: number
  details?: string // Additional technical details
}

export interface ErrorContextType {
  errors: AppError[]
  addError: (error: Omit<AppError, 'id' | 'timestamp'>) => void
  removeError: (id: string) => void
  clearAllErrors: () => void
  clearErrorsBySource: (source: string) => void
}

const ErrorContext = createContext<ErrorContextType | null>(null)

export const useErrors = () => {
  const context = useContext(ErrorContext)
  if (!context) {
    throw new Error('useErrors must be used within ErrorProvider')
  }
  return context
}

interface ErrorProviderProps {
  children: React.ReactNode
}

export const ErrorProvider: React.FC<ErrorProviderProps> = ({ children }) => {
  const [errors, setErrors] = useState<AppError[]>([])

  const addError = useCallback((error: Omit<AppError, 'id' | 'timestamp'>) => {
    const newError: AppError = {
      ...error,
      id: `error_${Date.now()}_${Math.random().toString(36).substring(2)}`,
      timestamp: Date.now()
    }

    setErrors(prev => {
      // Check for duplicate errors by title and source within last 10 seconds
      const recentDuplicate = prev.find(e => 
        e.title === newError.title && 
        e.source === newError.source &&
        (Date.now() - e.timestamp) < 10000
      )
      
      if (recentDuplicate) {
        return prev // Don't add duplicate
      }

      // Add new error to the beginning and keep only the 5 most recent
      const updated = [newError, ...prev].slice(0, 5)
      return updated
    })
  }, [])

  const removeError = useCallback((id: string) => {
    setErrors(prev => prev.filter(e => e.id !== id))
  }, [])

  const clearAllErrors = useCallback(() => {
    setErrors([])
  }, [])

  const clearErrorsBySource = useCallback((source: string) => {
    setErrors(prev => prev.filter(e => e.source !== source))
  }, [])

  const value: ErrorContextType = {
    errors,
    addError,
    removeError,
    clearAllErrors,
    clearErrorsBySource
  }

  return (
    <ErrorContext.Provider value={value}>
      {children}
    </ErrorContext.Provider>
  )
}

// Utility functions for common error scenarios
export const createRPCError = (chainId: number, message: string, details?: string): Omit<AppError, 'id' | 'timestamp'> => ({
  title: 'RPC Connection Failed',
  message: `Chain ${chainId}: ${message}`,
  severity: 'error',
  source: 'RPC',
  chainId,
  details
})

export const createKickableError = (auctionAddress: string, chainId: number, details?: string): Omit<AppError, 'id' | 'timestamp'> => ({
  title: 'Kickable Status Check Failed',
  message: `Unable to check kickable status for auction ${auctionAddress.substring(0, 8)}...`,
  severity: 'warning',
  source: 'RPC',
  chainId,
  details
})

export const createAPIError = (endpoint: string, message: string): Omit<AppError, 'id' | 'timestamp'> => ({
  title: 'API Request Failed',
  message: `${endpoint}: ${message}`,
  severity: 'error',
  source: 'API',
  details: `Failed to fetch data from ${endpoint}`
})

export default ErrorProvider