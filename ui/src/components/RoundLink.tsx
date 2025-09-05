import React from 'react';
import InternalLink from './InternalLink';

interface RoundLinkProps {
  chainId: number;
  auctionAddress: string;
  roundId: number | string;
  className?: string;
  size?: 'sm' | 'md' | 'lg';
  showArrow?: boolean;
}

/**
 * Standardized Round Link component for consistent Round ID display across all tables and pages
 * Uses the same styling as auction addresses (font-mono text-sm)
 */
const RoundLink: React.FC<RoundLinkProps> = ({
  chainId,
  auctionAddress,
  roundId,
  className = '',
  size = 'sm',
  showArrow = true,
}) => {
  const sizeClasses = {
    sm: 'text-xs',
    md: 'text-sm',
    lg: 'text-base'
  };

  return (
    <InternalLink
      to={`/round/${chainId}/${auctionAddress}/${roundId}`}
      variant="round"
      showArrow={showArrow}
      className={`font-mono ${sizeClasses[size]} ${className}`}
    >
      R{roundId}
    </InternalLink>
  );
};

export default RoundLink;