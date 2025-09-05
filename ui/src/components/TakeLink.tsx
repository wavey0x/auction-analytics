import React from 'react'
import InternalLink from './InternalLink'
import { Activity } from 'lucide-react'
import { cn } from '../lib/utils'

interface TakeLinkProps {
  chainId: number
  auctionAddress: string
  roundId: number
  takeSeq: number
  children?: React.ReactNode
  className?: string
  variant?: 'default' | 'icon' | 'minimal'
  size?: 'sm' | 'md' | 'lg'
  showArrow?: boolean
}

const TakeLink: React.FC<TakeLinkProps> = ({
  chainId,
  auctionAddress,
  roundId,
  takeSeq,
  children,
  className,
  variant = 'default',
  size = 'md',
  showArrow = true
}) => {
  const sizeClasses = {
    sm: 'text-xs',
    md: 'text-sm', 
    lg: 'text-base'
  }

  const iconSizes = {
    sm: 'h-3 w-3',
    md: 'h-4 w-4',
    lg: 'h-5 w-5'
  }

  const takeId = `${auctionAddress}-${roundId}-${takeSeq}`
  
  if (variant === 'icon') {
    return (
      <InternalLink 
        to={`/take/${chainId}/${auctionAddress}/${roundId}/${takeSeq}`}
        className={cn(
          "inline-flex items-center justify-center p-1 rounded hover:bg-gray-700/50 transition-colors",
          "text-primary-400 hover:text-primary-300",
          className
        )}
      >
        <Activity className={iconSizes[size]} />
      </InternalLink>
    )
  }

  if (variant === 'minimal') {
    return (
      <InternalLink 
        to={`/take/${chainId}/${auctionAddress}/${roundId}/${takeSeq}`}
        variant="take"
        showArrow={showArrow}
        className={cn(
          sizeClasses[size],
          className
        )}
      >
        {children || `T${takeSeq}`}
      </InternalLink>
    )
  }

  // Default variant - using new InternalLink variant system
  return (
    <InternalLink 
      to={`/take/${chainId}/${auctionAddress}/${roundId}/${takeSeq}`}
      variant="take"
      showArrow={showArrow}
      className={cn(
        sizeClasses[size],
        className
      )}
    >
      {children || `T${takeSeq}`}
    </InternalLink>
  )
}

export default TakeLink